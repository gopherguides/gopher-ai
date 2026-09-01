#!/usr/bin/env python3

import json
import os
import re
import resource
import shlex
import shutil
import signal
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
    "export",
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
KNOWN_SHELL_VARIABLES = {
    "BASH_SOURCE",
    "CI",
    "EUID",
    "HOME",
    "HOSTNAME",
    "IFS",
    "LANG",
    "LINENO",
    "OLDPWD",
    "OPTARG",
    "OPTIND",
    "PATH",
    "PPID",
    "PWD",
    "RANDOM",
    "REPLY",
    "SECONDS",
    "SHELL",
    "SHLVL",
    "TERM",
    "TMPDIR",
    "UID",
    "USER",
    "_",
}.union(RUNTIME_VARIABLES)
EXECUTION_OUTPUT_LIMIT = 64 * 1024
FENCE_START = re.compile(r"^\s*```(bash|sh|shell|zsh)(?:\s+[^`]*)?\s*$")
FENCE_END = re.compile(r"^\s*```\s*$")


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


def heredoc_specifiers(line):
    specifiers = []
    quote = None
    escaped = False
    index = 0
    while index < len(line):
        character = line[index]
        if escaped:
            escaped = False
            index += 1
            continue
        if character == "\\" and quote != "'":
            escaped = True
            index += 1
            continue
        if quote:
            if character == quote:
                quote = None
            index += 1
            continue
        if character in {"'", '"'}:
            quote = character
            index += 1
            continue
        if character == "#" and (
            index == 0 or line[index - 1].isspace() or line[index - 1] in ";&|(){}<>"
        ):
            break
        if not line.startswith("<<", index) or line.startswith("<<<", index):
            index += 1
            continue
        index += 2
        strip_tabs = index < len(line) and line[index] == "-"
        if strip_tabs:
            index += 1
        while index < len(line) and line[index] in {" ", "\t"}:
            index += 1
        delimiter = []
        while index < len(line):
            character = line[index]
            if character in " \t\r\n;&|<>()":
                break
            if character in {"'", '"'}:
                delimiter_quote = character
                index += 1
                while index < len(line) and line[index] != delimiter_quote:
                    delimiter.append(line[index])
                    index += 1
                if index < len(line):
                    index += 1
                continue
            if character == "\\" and index + 1 < len(line):
                delimiter.append(line[index + 1])
                index += 2
                continue
            delimiter.append(character)
            index += 1
        if delimiter:
            specifiers.append(("".join(delimiter), strip_tabs))
    return specifiers


def without_heredoc_bodies(code):
    pending = []
    retained = []
    for line in code.splitlines(keepends=True):
        content = line.rstrip("\r\n")
        if pending:
            delimiter, strip_tabs = pending[0]
            candidate = content.lstrip("\t") if strip_tabs else content
            if candidate == delimiter:
                pending.pop(0)
            retained.append("\n" if line.endswith(("\n", "\r")) else "")
            continue
        retained.append(line)
        pending.extend(heredoc_specifiers(content))
    return "".join(retained)


def without_shell_comments(code):
    retained = []
    quote = None
    escaped = False
    index = 0
    while index < len(code):
        character = code[index]
        if escaped:
            retained.append(character)
            escaped = False
            index += 1
            continue
        if character == "\\" and quote != "'":
            retained.append(character)
            escaped = True
            index += 1
            continue
        if quote:
            retained.append(character)
            if character == quote:
                quote = None
            index += 1
            continue
        if character in {"'", '"'}:
            retained.append(character)
            quote = character
            index += 1
            continue
        if character == "#" and (
            not retained or retained[-1].isspace() or retained[-1] in ";&|(){}<>"
        ):
            while index < len(code) and code[index] not in "\r\n":
                index += 1
            continue
        retained.append(character)
        index += 1
    return "".join(retained)


def shell_code_projection(code):
    return without_shell_comments(without_heredoc_bodies(code))


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
        text = re.sub(r"^(?:if|then|elif|else|while|until|do|!)(?:\s+|$)", "", text)
        if text == previous:
            break
    if not text or re.match(r"^(?:fi|done|esac|for|select|case|function|\{|\})\b", text):
        return []
    try:
        return shlex.split(text, comments=True, posix=True)
    except ValueError:
        return ["<unparseable>"]


def set_execution_output_limit():
    resource.setrlimit(
        resource.RLIMIT_FSIZE,
        (EXECUTION_OUTPUT_LIMIT, EXECUTION_OUTPUT_LIMIT),
    )


def classify_block(block):
    code = shell_code_projection(block.code)
    tiers = []
    results = []
    unknown = set()
    red = set()
    if re.search(r"\$\(|`[^`]+`|[<>]\(", code):
        unknown.add("command substitution")
        tiers.append("red")
    if re.search(r"(?:^|[^<])>{1,2}(?:[^&]|$)", code, re.MULTILINE):
        unknown.add("output redirection")
        tiers.append("red")
    for segment in command_segments(code):
        if re.match(r"^\s*(?:[({]|case\b|for\b|select\b|function\b)", segment):
            unknown.add("compound command")
            tiers.append("red")
            continue
        tokens = command_tokens(segment)
        if not tokens:
            continue
        command = tokens[0]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", command):
            unknown.add("environment assignment")
            tiers.append("red")
            continue
        if "/" in command:
            unknown.add("executable path")
            tiers.append("red")
            continue
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
        elif command == "printf" and any(token.startswith("-v") for token in tokens[1:]):
            unknown.add("printf -v")
            tiers.append("red")
        elif command in YELLOW_COMMANDS:
            tiers.append("yellow")
        elif command in GREEN_COMMANDS:
            tiers.append("green")
        else:
            unknown.add(command)
            tiers.append("red")

    if re.search(r"\b(?:curl|wget)\b[^\n|]*\|\s*(?:sh|bash|eval|exec)\b", code):
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
    with tempfile.TemporaryFile() as captured:
        process = subprocess.Popen(
            command,
            cwd=execution_root,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=captured,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            preexec_fn=set_execution_output_limit,
        )
        try:
            returncode = process.wait(timeout=5)
            timed_out = False
        except subprocess.TimeoutExpired:
            timed_out = True
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            returncode = process.returncode
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        output_size = os.fstat(captured.fileno()).st_size
    if timed_out:
        return [
            finding(
                block,
                "warning",
                "execution",
                "GREEN-tier execution exceeded the 5 second timeout",
                "Make the example bounded or classify it as syntax-check only.",
            )
        ]
    if output_size >= EXECUTION_OUTPUT_LIMIT:
        return [
            finding(
                block,
                "warning",
                "execution",
                "GREEN-tier execution exceeded the 64 KiB output limit",
                "Bound the example output or classify it as syntax-check only.",
            )
        ]
    if returncode == 0:
        return []
    return [
        finding(
            block,
            "warning",
            "execution",
            f"GREEN-tier execution failed with status {returncode}",
            "Correct the example or move it to a syntax-check-only classification.",
        )
    ]


def shell_quote_states(code):
    states = []
    quote = None
    escaped = False
    for character in code:
        states.append(quote)
        if escaped:
            escaped = False
            continue
        if character == "\\" and quote != "'":
            escaped = True
            continue
        if quote:
            if character == quote:
                quote = None
            continue
        if character in {"'", '"'}:
            quote = character
    return states


def variable_references(code, states):
    references = []
    index = 0
    while index < len(code):
        backslashes = 0
        previous = index - 1
        while previous >= 0 and code[previous] == "\\":
            backslashes += 1
            previous -= 1
        if code[index] != "$" or states[index] == "'" or backslashes % 2:
            index += 1
            continue
        braced = re.match(r"\$\{([A-Za-z_][A-Za-z0-9_]*)([^}]*)\}", code[index:])
        plain = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)", code[index:])
        match = braced or plain
        if not match:
            index += 1
            continue
        tail = match.group(2) if braced else ""
        references.append(
            {
                "name": match.group(1),
                "position": index,
                "unquoted": states[index] is None,
                "defaulted": bool(re.match(r"^:?[+?=\-]", tail)),
            }
        )
        index += len(match.group(0))
    return references


def variable_definition_positions(code, states):
    positions = {}
    patterns = (
        r"(?<![-\w$])([A-Za-z_][A-Za-z0-9_]*)=",
        r"\b(?:for|select|read|local|declare|typeset)\s+(?:-[A-Za-z]+\s+)*([A-Za-z_][A-Za-z0-9_]*)\b",
    )
    for pattern in patterns:
        for match in re.finditer(pattern, code):
            position = match.start(1)
            if states[position] is None:
                positions.setdefault(match.group(1), []).append(position)
    return positions


def semantic_variable_findings(block, code):
    states = shell_quote_states(code)
    references = variable_references(code, states)
    definitions = variable_definition_positions(code, states)
    unquoted = sorted({reference["name"] for reference in references if reference["unquoted"]})
    undefined = sorted(
        {
            reference["name"]
            for reference in references
            if reference["name"] not in KNOWN_SHELL_VARIABLES
            and not reference["defaulted"]
            and not any(
                position < reference["position"]
                for position in definitions.get(reference["name"], [])
            )
        }
    )
    results = []
    if unquoted:
        results.append(
            finding(
                block,
                "warning",
                "review",
                f"Unquoted variable expansion may split or glob: {', '.join(unquoted)}",
                "Double-quote expansions unless intentional splitting is required.",
            )
        )
    if undefined:
        results.append(
            finding(
                block,
                "warning",
                "review",
                f"Variables are used before definition or documentation: {', '.join(undefined)}",
                "Assign each variable earlier, use a documented runtime variable, or provide an explicit default.",
            )
        )
    return results


def external_output_findings(block, code):
    results = []
    pipefail = bool(re.search(r"\bset\s+(?:-[^\n]*o\s+pipefail|-o\s+pipefail)\b", code))
    for line in code.splitlines():
        curl_json = re.search(r"\bcurl\b([^|\n]*)\|\s*jq\b", line)
        if curl_json and not re.search(r"(?:^|\s)(?:-f\b|--fail(?:-with-body)?\b)", curl_json.group(1)):
            results.append(
                finding(
                    block,
                    "warning",
                    "review",
                    "curl output is parsed as JSON without HTTP failure checking",
                    "Use --fail or --fail-with-body and handle request failures before parsing JSON.",
                )
            )
        direct_json = re.search(r"\b(curl|gh|git|go|docker|npm|npx)\b[^|\n]*\|\s*jq\b", line)
        if direct_json and not pipefail and not re.search(r"^\s*if\b|\|\|\s*\S|&&\s*\S", line):
            results.append(
                finding(
                    block,
                    "warning",
                    "review",
                    f"{direct_json.group(1)} output is piped to jq without pipeline error handling",
                    "Enable pipefail or check the producer and parser statuses explicitly.",
                )
            )
        parsed = re.search(
            r"\b(gh|git)\b([^|\n]*)\|\s*(?:awk|sed|cut|head|tail|rg|grep)\b",
            line,
        )
        if parsed:
            options = parsed.group(2)
            stable = re.search(r"(?:--json|--format|--template|--jq|--porcelain|--pretty(?:=|\s+format))\b", options)
            if not stable:
                results.append(
                    finding(
                        block,
                        "warning",
                        "review",
                        f"{parsed.group(1)} human-readable output is parsed without a stable format option",
                        "Request structured or explicitly formatted output before parsing it.",
                    )
                )
        first_line = re.search(
            r"\b(curl|gh|git|go|docker|npm|npx)\b([^|\n]*)\|\s*"
            r"(?:head\s+(?:-n\s*)?1\b|sed\s+[^|\n]*1p\b|awk\s+[^|\n]*NR\s*==\s*1)",
            line,
        )
        if first_line and not re.search(
            r"(?:--json|--format|--template|--jq|--porcelain|--pretty(?:=|\s+format))\b",
            first_line.group(2),
        ):
            results.append(
                finding(
                    block,
                    "warning",
                    "review",
                    f"{first_line.group(1)} first-line output may include banners or progress text",
                    "Request a stable machine-readable field instead of selecting the first display line.",
                )
            )
    return results


def review_findings(block):
    code = shell_code_projection(block.code)
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
        if re.search(pattern, code, re.MULTILINE):
            results.append(finding(block, "warning", "review", message, fix))
    results.extend(semantic_variable_findings(block, code))
    results.extend(external_output_findings(block, code))
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
