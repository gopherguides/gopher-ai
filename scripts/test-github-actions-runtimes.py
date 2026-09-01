#!/usr/bin/env python3

import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"
PLUGIN_TEMPLATES = ROOT / "plugins"
AGENT_SKILLS = ROOT / "agent-skills"
CHECKOUT_V7_SHA = "3d3c42e5aac5ba805825da76410c181273ba90b1"
SUPPORTED_REFS = {
    "actions/checkout": {"v7", CHECKOUT_V7_SHA},
    "actions/setup-go": {"v7"},
    "actions/setup-node": {"v7"},
}
ACTION_PATTERN = re.compile(
    r'''^(\s*)(-\s+)?uses:\s*(["']?)(actions/(?:checkout|setup-go|setup-node))'''
    r'''@([^\s#"']+)\3(?:\s*(?:#.*)?)$'''
)


def normalize_workflow_line(line):
    match = re.match(r"^(\s*)# ?(.*)$", line)
    if match:
        return f"{match.group(1)}{match.group(2)}"
    return line


def parser_failures():
    cases = {
        "      - uses: actions/checkout@v7": ("actions/checkout", "v7"),
        "      - uses: 'actions/setup-go@v5'": ("actions/setup-go", "v5"),
        '      - uses: "actions/setup-node@v4" # stale': (
            "actions/setup-node",
            "v4",
        ),
        "        uses: 'actions/setup-node@v4'": ("actions/setup-node", "v4"),
        "  #     - uses: actions/setup-go@v6": ("actions/setup-go", "v6"),
    }
    failures = []
    for line, expected in cases.items():
        match = ACTION_PATTERN.match(normalize_workflow_line(line))
        actual = None if match is None else (match.group(4), match.group(5))
        if actual != expected:
            failures.append(f"action parser missed fixture: {line}")
    return failures


def cache_parser_failures():
    cases = (
        (
            [
                "      - uses: actions/setup-node@v7",
                "        with:",
                "          package-manager-cache: false",
            ],
            0,
            True,
        ),
        (
            [
                "      - name: Set up Node",
                "        with:",
                "          package-manager-cache: false",
                "        uses: actions/setup-node@v7",
            ],
            3,
            True,
        ),
        (
            [
                "      - name: Set up Node",
                "        uses: actions/setup-node@v7",
                "      - name: Unrelated step",
                "        with:",
                "          package-manager-cache: false",
            ],
            1,
            False,
        ),
    )
    failures = []
    for lines, uses_index, expected in cases:
        match = ACTION_PATTERN.match(lines[uses_index])
        actual = step_has_cache_disabled(
            lines,
            uses_index,
            len(match.group(1)),
            bool(match.group(2)),
        )
        if actual != expected:
            failures.append(f"cache parser failed fixture at uses line {uses_index + 1}")
    return failures


def workflow_files():
    return sorted(
        (
            *WORKFLOWS.glob("*.yml"),
            *WORKFLOWS.glob("*.yaml"),
            *PLUGIN_TEMPLATES.glob("*/templates/**/*.yml"),
            *PLUGIN_TEMPLATES.glob("*/templates/**/*.yaml"),
            *AGENT_SKILLS.glob("**/*.md"),
        )
    )


def step_has_cache_disabled(lines, start, indentation, list_marker):
    step_start = start
    step_indentation = indentation
    if not list_marker:
        for index in range(start - 1, -1, -1):
            match = re.match(r"^(\s*)-\s+", lines[index])
            if match and len(match.group(1)) < indentation:
                step_start = index
                step_indentation = len(match.group(1))
                break

    for index, line in enumerate(lines[step_start:], start=step_start):
        match = re.match(r"^(\s*)-\s+", line)
        if index > step_start and match and len(match.group(1)) <= step_indentation:
            break
        if re.match(r"^\s+package-manager-cache:\s*false\s*(?:#.*)?$", line):
            return True
    return False


def main():
    failures = parser_failures() + cache_parser_failures()
    discovered = 0

    for path in workflow_files():
        lines = [normalize_workflow_line(line) for line in path.read_text().splitlines()]
        for index, line in enumerate(lines):
            match = ACTION_PATTERN.match(line)
            if not match:
                continue

            discovered += 1
            indentation, list_marker, _, action, action_ref = match.groups()
            location = f"{path.relative_to(ROOT)}:{index + 1}"
            if action_ref not in SUPPORTED_REFS[action]:
                failures.append(f"{location}: unsupported {action}@{action_ref}")
            if action == "actions/setup-node" and not step_has_cache_disabled(
                lines, index, len(indentation), bool(list_marker)
            ):
                failures.append(
                    f"{location}: setup-node must set package-manager-cache: false"
                )

    if discovered == 0:
        failures.append("no checkout, setup-go, or setup-node workflow actions found")

    if failures:
        print("GitHub Actions runtime policy failed:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print(f"GitHub Actions runtime policy passed ({discovered} action uses).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
