#!/usr/bin/env python3

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


GREEN_COMMANDS = {
    "[",
    "basename",
    "cat",
    "comm",
    "cut",
    "dirname",
    "echo",
    "export",
    "false",
    "grep",
    "head",
    "jq",
    "ls",
    "printf",
    "pwd",
    "readlink",
    "realpath",
    "stat",
    "tail",
    "test",
    "tr",
    "true",
    "type",
    "uniq",
    "wc",
    "which",
}
YELLOW_COMMANDS = {
    "awk",
    "curl",
    "date",
    "diff",
    "docker",
    "env",
    "file",
    "find",
    "gh",
    "go",
    "golangci-lint",
    "mktemp",
    "node",
    "npm",
    "npx",
    "rg",
    "sed",
    "sort",
    "tee",
    "wget",
}
RED_COMMANDS = {
    "chmod",
    "chown",
    "dd",
    "eval",
    "exec",
    "kill",
    "killall",
    "mkfs",
    "mount",
    "rm",
    "rmdir",
    "sudo",
    "umount",
}
RED_GIT_COMMANDS = {"clean", "push"}
GREEN_GIT_COMMANDS = {"branch", "diff", "log", "remote", "rev-parse", "show", "status"}
RUNTIME_VARIABLES = (
    "ARGUMENTS",
    "CLAUDE_PLUGIN_ROOT",
    "DIFF",
    "DRY_RUN",
    "FINDINGS",
    "LLM_CHOICE",
    "MODEL",
    "REVIEW_JSON",
    "SKILL_ARGS",
    "STAGED",
    "TARGET_PATH",
)
RUNTIME_VARIABLE_PATTERN = re.compile(
    r"\$(?:\{(?:" + "|".join(RUNTIME_VARIABLES) + r")\}|(?:"
    + "|".join(RUNTIME_VARIABLES)
    + r")\b)"
)
FENCE_START = re.compile(r"^\s*```(bash|sh|shell|zsh)(?:\s+[^`]*)?\s*$")
FENCE_END = re.compile(r"^\s*```\s*$")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=(?:'[^']*'|\"[^\"]*\"|[^\s]*)\s*")


@dataclass(frozen=True)
class Block:
    file: str
    source: Path
    start_line: int
    end_line: int
    language: str
    code: str


def finding(block, severity, layer, message, suggested_fix):
    return {
        "file": block.file,
        "start_line": block.start_line,
        "end_line": block.end_line,
        "severity": severity,
        "layer": layer,
        "finding": message,
        "suggested_fix": suggested_fix,
    }


def path_finding(path, message):
    return {
        "file": path,
        "start_line": 0,
        "end_line": 0,
        "severity": "error",
        "layer": "static",
        "finding": message,
        "suggested_fix": "Provide one existing Markdown file or directory.",
    }


def parse_arguments(arguments):
    json_mode = False
    targets = []
    for argument in arguments:
        if argument == "--json":
            json_mode = True
        elif argument.startswith("-"):
            raise ValueError(f"Unknown option: {argument}")
        else:
            targets.append(argument)
    if len(targets) > 1:
        raise ValueError("Accepts at most one file or directory path")
    return json_mode, targets[0] if targets else None


def display_path(path, root):
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def discover_files(root, target):
    if target:
        path = (root / target).resolve() if not Path(target).is_absolute() else Path(target).resolve()
        if not path.exists():
            raise ValueError(f"Path does not exist: {target}")
        if path.is_file():
            if path.suffix != ".md":
                raise ValueError(f"File is not Markdown: {target}")
            return [path]
        return sorted(item for item in path.rglob("*.md") if item.is_file())

    files = set()
    for pattern in (
        "plugins/*/commands/**/*.md",
        "plugins/*/skills/**/*.md",
        "shared/commands/**/*.md",
    ):
        files.update(item.resolve() for item in root.glob(pattern) if item.is_file())
    return sorted(files)


def extract_blocks(path, root):
    blocks = []
    extraction_findings = []
    lines = path.read_text(encoding="utf-8").splitlines()
    active = None
    content = []
    for line_number, line in enumerate(lines, 1):
        if active is None:
            match = FENCE_START.match(line)
            if match:
                active = (match.group(1), line_number + 1)
                content = []
            continue
        if FENCE_END.match(line):
            language, start_line = active
            blocks.append(
                Block(
                    file=display_path(path, root),
                    source=path,
                    start_line=start_line,
                    end_line=max(start_line, line_number - 1),
                    language=language,
                    code="\n".join(content) + "\n",
                )
            )
            active = None
            content = []
            continue
        content.append(line)

    if active is not None:
        language, start_line = active
        block = Block(
            file=display_path(path, root),
            source=path,
            start_line=start_line,
            end_line=max(start_line, len(lines)),
            language=language,
            code="\n".join(content) + "\n",
        )
        blocks.append(block)
        extraction_findings.append(
            finding(
                block,
                "error",
                "static",
                f"Unclosed {language} fence beginning at Markdown line {start_line - 1}",
                "Close the fenced code block with three backticks.",
            )
        )
    return blocks, extraction_findings


def mapped_line(block, output):
    matches = re.findall(r"(?:line\s+|:\s*)(\d+):", output)
    if not matches:
        return block.start_line
    source_line = block.start_line + int(matches[-1]) - 1
    return min(max(source_line, block.start_line), block.end_line)


def clean_process_output(output, script_path):
    cleaned = output.replace(str(script_path), "shell block").strip()
    return " ".join(cleaned.split()) or "shell parser returned a nonzero status"


def syntax_findings(block, script_path):
    results = []
    parser_name = "bash" if block.language in {"bash", "shell"} else block.language
    parser = shutil.which(parser_name)
    if not parser:
        severity = "error" if parser_name in {"bash", "sh"} else "info"
        message = f"{parser_name} is unavailable"
        fix = f"Install {parser_name} to validate {block.language} syntax."
        results.append(finding(block, severity, "static", message, fix))
        return results

    completed = subprocess.run(
        [parser, "-n", str(script_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode:
        output = completed.stderr or completed.stdout
        line = mapped_line(block, output)
        results.append(
            finding(
                block,
                "error",
                "static",
                f"Syntax error at Markdown line {line}: {clean_process_output(output, script_path)}",
                "Correct the shell syntax at the mapped source line.",
            )
        )

    if block.language == "zsh":
        return results
    shellcheck = shutil.which("shellcheck")
    if not shellcheck:
        results.append(
            finding(
                block,
                "info",
                "static",
                "ShellCheck is unavailable — skipped ShellCheck analysis",
                "Install ShellCheck to enable additional static analysis.",
            )
        )
        return results
    shell = "sh" if block.language == "sh" else "bash"
    checked = subprocess.run(
        [
            shellcheck,
            "--format=json",
            f"--shell={shell}",
            "--exclude=SC1091,SC2086,SC2034",
            str(script_path),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        messages = json.loads(checked.stdout or "[]")
    except json.JSONDecodeError:
        messages = []
    for message in messages:
        level = message.get("level", "warning")
        severity = "error" if level == "error" else "warning" if level == "warning" else "info"
        line = min(
            max(block.start_line + int(message.get("line", 1)) - 1, block.start_line),
            block.end_line,
        )
        results.append(
            finding(
                block,
                severity,
                "static",
                f"ShellCheck SC{message.get('code')} at Markdown line {line}: {message.get('message', '')}",
                "Apply the ShellCheck guidance or document why the construct is required.",
            )
        )
    return results


def command_segments(code):
    segments = []
    current = []
    quote = None
    escaped = False
    index = 0
    while index < len(code):
        character = code[index]
        if escaped:
            current.append(character)
            escaped = False
            index += 1
            continue
        if character == "\\" and quote != "'":
            current.append(character)
            escaped = True
            index += 1
            continue
        if quote:
            current.append(character)
            if character == quote:
                quote = None
            index += 1
            continue
        if character in {"'", '"'}:
            current.append(character)
            quote = character
            index += 1
            continue
        if character == "#" and (not current or current[-1].isspace()):
            while index < len(code) and code[index] != "\n":
                index += 1
            continue
        if character in {";", "|", "&", "\n"}:
            segment = "".join(current).strip()
            if segment:
                segments.append(segment)
            current = []
            while index + 1 < len(code) and code[index + 1] in {";", "|", "&"}:
                index += 1
            index += 1
            continue
        current.append(character)
        index += 1
    segment = "".join(current).strip()
    if segment:
        segments.append(segment)
    return segments


def command_tokens(segment):
    text = segment.strip()
    if not text:
        return []
    while True:
        previous = text
        text = re.sub(r"^(?:if|then|elif|else|while|until|do|!)\s+", "", text)
        text = ASSIGNMENT.sub("", text)
        if text == previous:
            break
    if not text or re.match(r"^(?:fi|done|esac|for|select|case|function|\{|\})\b", text):
        return []
    try:
        return shlex.split(text, comments=True, posix=True)
    except ValueError:
        return ["<unparseable>"]


def classify_block(block):
    tiers = []
    results = []
    unknown = set()
    red = set()
    if re.search(r"\$\(|`[^`]+`|[<>]\(", block.code):
        unknown.add("command substitution")
        tiers.append("red")
    if re.search(r"(?:^|[^<])>{1,2}(?:[^&]|$)", block.code, re.MULTILINE):
        unknown.add("output redirection")
        tiers.append("red")
    for segment in command_segments(block.code):
        if re.match(r"^\s*(?:[({]|case\b|for\b|select\b|function\b)", segment):
            unknown.add("compound command")
            tiers.append("red")
            continue
        tokens = command_tokens(segment)
        if not tokens:
            continue
        command = Path(tokens[0]).name
        if command == "git":
            subcommand = next((token for token in tokens[1:] if not token.startswith("-")), "")
            if subcommand in RED_GIT_COMMANDS or (
                subcommand in {"checkout", "restore"} and "." in tokens[2:]
            ) or (subcommand == "reset" and "--hard" in tokens):
                red.add("git " + " ".join(tokens[1:]))
                tiers.append("red")
            elif subcommand in GREEN_GIT_COMMANDS:
                tiers.append("yellow")
            else:
                unknown.add("git" + (f" {subcommand}" if subcommand else ""))
                tiers.append("red")
        elif command in RED_COMMANDS:
            red.add(command)
            tiers.append("red")
        elif command in YELLOW_COMMANDS:
            tiers.append("yellow")
        elif command in GREEN_COMMANDS:
            tiers.append("green")
        else:
            unknown.add(command)
            tiers.append("red")

    if re.search(r"\b(?:curl|wget)\b[^\n|]*\|\s*(?:sh|bash|eval|exec)\b", block.code):
        red.add("pipe to shell")
        tiers.append("red")
    for command in sorted(red):
        results.append(
            finding(
                block,
                "warning",
                "classification",
                f"RED-tier command: {command}",
                "Verify the destructive command is intentional; this block was not executed.",
            )
        )
    for command in sorted(unknown):
        results.append(
            finding(
                block,
                "warning",
                "classification",
                f"Unknown command classified conservatively: {command}",
                "Add an explicit safety classification before allowing execution.",
            )
        )
    if "red" in tiers:
        return "red", results
    if "yellow" in tiers:
        return "yellow", results
    return "green", results


def execution_findings(block, script_path, tier, execution_root):
    if tier != "green":
        return []
    if RUNTIME_VARIABLE_PATTERN.search(block.code):
        return [
            finding(
                block,
                "info",
                "execution",
                "Block contains plugin runtime variables — skipped execution",
                "Run the block only inside its owning plugin workflow.",
            )
        ]
    shell_name = "bash" if block.language in {"bash", "shell"} else block.language
    shell = shutil.which(shell_name)
    if not shell:
        return []
    command = [shell]
    if shell_name == "bash":
        command.append("--restricted")
    command.append(str(script_path))
    environment = {
        "HOME": str(execution_root),
        "TMPDIR": str(execution_root),
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    }
    try:
        completed = subprocess.run(
            command,
            cwd=execution_root,
            env=environment,
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return [
            finding(
                block,
                "warning",
                "execution",
                "GREEN-tier execution exceeded the 5 second timeout",
                "Make the example bounded or classify it as syntax-check only.",
            )
        ]
    if completed.returncode == 0:
        return []
    output = clean_process_output(completed.stderr or completed.stdout, script_path)
    return [
        finding(
            block,
            "warning",
            "execution",
            f"GREEN-tier execution failed with status {completed.returncode}: {output}",
            "Correct the example or move it to a syntax-check-only classification.",
        )
    ]


def review_findings(block):
    checks = (
        (
            r"\bmktemp\s+\S*X{6}\.[A-Za-z0-9]+",
            "mktemp template has characters after XXXXXX and is not portable to macOS",
            "End the template with XXXXXX and rename the result if an extension is needed.",
        ),
        (
            r"\bsed\s+-i\s+['\"]",
            "sed -i without a backup suffix is not portable to macOS",
            "Use a backup suffix or detect the platform-specific syntax.",
        ),
        (r"\bgrep\s+-P\b", "grep -P is unavailable on macOS", "Use grep -E."),
        (r"\breadlink\s+-f\b", "readlink -f is unavailable on macOS", "Use realpath or cd with pwd."),
        (r"\bdate\s+-d\b", "date -d uses GNU-only syntax", "Detect the platform or use portable date handling."),
        (r"\bxargs\s+-r\b", "xargs -r is a GNU extension", "Filter empty input before invoking xargs."),
        (r"(?:^|[;&|]\s*)tac\b", "tac is unavailable on macOS by default", "Use tail -r or a portable sed expression."),
        (
            r"[^\n]+&&[^\n]+\|\|[^\n]+",
            "A && B || C is not equivalent to if/else when B can fail",
            "Use an explicit if statement.",
        ),
        (
            r"\[\s+-z\s+\$[A-Za-z_][A-Za-z0-9_]*\s*\]",
            "Unquoted variable in -z test can split or disappear",
            "Quote the variable expansion.",
        ),
        (
            r"for\s+\w+\s+in\s+\$\(ls\b",
            "Iterating over ls output breaks on whitespace and glob characters",
            "Iterate over the glob directly.",
        ),
        (
            r"\bcat\s+\S+\s*\|\s*grep\b",
            "Useless cat pipeline obscures grep error handling",
            "Pass the file directly to grep.",
        ),
    )
    results = []
    for pattern, message, fix in checks:
        if re.search(pattern, block.code, re.MULTILINE):
            results.append(finding(block, "warning", "review", message, fix))
    return results


def validate(root, files):
    blocks = []
    findings = []
    for path in files:
        extracted, extraction_findings = extract_blocks(path, root)
        blocks.extend(extracted)
        findings.extend(extraction_findings)

    temp_parent = os.environ.get("TMPDIR")
    with tempfile.TemporaryDirectory(prefix="validate-skills-", dir=temp_parent) as temp_name:
        temp_root = Path(temp_name)
        for index, block in enumerate(blocks, 1):
            suffix = ".zsh" if block.language == "zsh" else ".sh"
            script_path = temp_root / f"block-{index:03d}{suffix}"
            script_path.write_text(block.code, encoding="utf-8")
            findings.extend(syntax_findings(block, script_path))
            tier, classification = classify_block(block)
            findings.extend(classification)
            findings.extend(execution_findings(block, script_path, tier, temp_root))
            findings.extend(review_findings(block))
    return blocks, findings


def build_report(files, blocks, findings):
    counts = Counter(item["severity"] for item in findings)
    return {
        "files_scanned": len(files),
        "blocks_found": len(blocks),
        "findings": findings,
        "summary": {
            "errors": counts["error"],
            "warnings": counts["warning"],
            "info": counts["info"],
        },
    }


def table_value(value):
    return str(value).replace("|", "\\|").replace("\n", " ")


def render_markdown(report):
    summary = report["summary"]
    lines = [
        "## Validation Report",
        "",
        f"**Files scanned:** {report['files_scanned']} | **Code blocks found:** {report['blocks_found']} | "
        f"**Findings:** {summary['errors']} errors, {summary['warnings']} warnings, {summary['info']} info",
    ]
    if not report["findings"]:
        lines.extend(
            [
                "",
                f"All {report['blocks_found']} code blocks in {report['files_scanned']} files passed validation.",
            ]
        )
        return "\n".join(lines)
    lines.extend(
        [
            "",
            "### Findings",
            "",
            "| # | File | Lines | Severity | Layer | Finding | Suggested Fix |",
            "|---|------|-------|----------|-------|---------|---------------|",
        ]
    )
    for index, item in enumerate(report["findings"], 1):
        lines.append(
            f"| {index} | {table_value(item['file'])} | {item['start_line']}-{item['end_line']} | "
            f"{item['severity']} | {item['layer']} | {table_value(item['finding'])} | "
            f"{table_value(item['suggested_fix'])} |"
        )
    return "\n".join(lines)


def main(arguments):
    try:
        json_mode, target = parse_arguments(arguments)
    except ValueError as error:
        json_mode = "--json" in arguments
        report = build_report([], [], [path_finding("", str(error))])
        print(json.dumps(report, indent=2) if json_mode else render_markdown(report))
        return 2

    root = Path.cwd()
    try:
        files = discover_files(root, target)
    except ValueError as error:
        report = build_report([], [], [path_finding(target or "", str(error))])
        print(json.dumps(report, indent=2) if json_mode else render_markdown(report))
        return 2

    blocks, findings = validate(root, files)
    report = build_report(files, blocks, findings)
    if json_mode:
        print(json.dumps(report, indent=2))
    else:
        print(render_markdown(report))
    return 1 if report["summary"]["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
