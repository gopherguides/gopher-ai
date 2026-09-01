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
BLOCK_ACTION_PATTERN = re.compile(
    r'''^(\s*)(-\s+)?(["']?)uses\3\s*:\s*(["']?)'''
    r'''(actions/(?:checkout|setup-go|setup-node))@([^\s,#"']+)\4'''
    r'''(?:\s*(?:#.*)?)$'''
)
FLOW_ACTION_PATTERN = re.compile(
    r'''^(\s*)-\s*\{.*?(["']?)uses\2\s*:\s*(["']?)'''
    r'''(actions/(?:checkout|setup-go|setup-node))@([^\s,}"']+)\3(?=\s*[,}])'''
)
FLOW_WITH_PATTERN = re.compile(
    r'''(?:\{|,)\s*(?:with|"with"|'with')\s*:\s*\{([^{}]*)\}'''
)
FLOW_CACHE_PATTERN = re.compile(
    r'''(?:^|,)\s*(?:package-manager-cache|"package-manager-cache"|'''
    r'''\'package-manager-cache\')\s*:\s*(?:false|"false"|'false')\s*(?=,|$)'''
)
ACTION_USES_PATTERN = re.compile(
    r'''(?:^|[\s{,])(["']?)uses\1\s*:\s*(["']?)'''
    r'''(actions/(?:checkout|setup-go|setup-node))@([^\s,#}"']+)\2'''
)


def normalize_workflow_line(line):
    match = re.match(r"^(\s*)# ?(.*)$", line)
    if match:
        return f"{match.group(1)}{match.group(2)}"
    return line


def parse_action(line):
    match = BLOCK_ACTION_PATTERN.match(line)
    if match:
        indentation, list_marker, _, _, action, action_ref = match.groups()
        return indentation, bool(list_marker), action, action_ref, False

    match = FLOW_ACTION_PATTERN.match(line)
    if match:
        indentation, _, _, action, action_ref = match.groups()
        return indentation, True, action, action_ref, True

    return None


def find_action_reference(line):
    match = ACTION_USES_PATTERN.search(line)
    return None if match is None else (match.group(3), match.group(4))


def parser_failures():
    cases = {
        "      - uses: actions/checkout@v7": ("actions/checkout", "v7"),
        "      - uses: 'actions/setup-go@v5'": ("actions/setup-go", "v5"),
        '      - uses: "actions/setup-node@v4" # stale': (
            "actions/setup-node",
            "v4",
        ),
        "        uses: 'actions/setup-node@v4'": ("actions/setup-node", "v4"),
        '      - "uses": actions/checkout@v4': ("actions/checkout", "v4"),
        "        'uses': actions/setup-go@v6": ("actions/setup-go", "v6"),
        "  #     - uses: actions/setup-go@v6": ("actions/setup-go", "v6"),
        "      - { uses: actions/checkout@v4 }": ("actions/checkout", "v4"),
        '      - { name: Checkout, "uses": "actions/checkout@v4" }': (
            "actions/checkout",
            "v4",
        ),
    }
    failures = []
    for line, expected in cases.items():
        parsed = parse_action(normalize_workflow_line(line))
        actual = None if parsed is None else (parsed[2], parsed[3])
        if actual != expected:
            failures.append(f"action parser missed fixture: {line}")

    fallback_line = "          uses: actions/checkout@v4,"
    if parse_action(fallback_line) is not None:
        failures.append("action parser unexpectedly accepted fallback fixture")
    if find_action_reference(fallback_line) != ("actions/checkout", "v4"):
        failures.append("action fallback missed unrecognized syntax fixture")
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
                "        with:",
                "          # package-manager-cache: false",
            ],
            1,
            False,
        ),
        (
            [
                "      - name: Set up Node",
                "        uses: actions/setup-node@v7",
                "        env:",
                "          package-manager-cache: false",
            ],
            1,
            False,
        ),
        (
            [
                "      - name: Set up Node",
                "        uses: actions/setup-node@v7",
                "        with:",
                "          cache-dependency-path:",
                "            package-manager-cache: false",
            ],
            1,
            False,
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
        (
            [
                "      - { uses: actions/setup-node@v7, with: { package-manager-cache: false } }",
            ],
            0,
            True,
        ),
        (
            [
                "      - { uses: actions/setup-node@v7, env: { package-manager-cache: false } }",
            ],
            0,
            False,
        ),
    )
    failures = []
    for lines, uses_index, expected in cases:
        parsed = parse_action(lines[uses_index])
        actual = action_has_cache_disabled(lines, uses_index, parsed)
        if actual != expected:
            failures.append(f"cache parser failed fixture at uses line {uses_index + 1}")

    generator_lines = [
        normalize_workflow_line(line)
        for line in (
            "  #     - uses: actions/setup-node@v7",
            "  #       with:",
            "  #         package-manager-cache: false",
        )
    ]
    generator_action = parse_action(generator_lines[0])
    if not action_has_cache_disabled(generator_lines, 0, generator_action):
        failures.append("cache parser missed commented generator fixture")
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
    step_key_indentation = indentation + 2 if list_marker else indentation
    if not list_marker:
        for index in range(start - 1, -1, -1):
            match = re.match(r"^(\s*)-\s+", lines[index])
            if match and len(match.group(1)) < indentation:
                step_start = index
                step_indentation = len(match.group(1))
                break

    step_end = len(lines)
    for index, line in enumerate(lines[step_start + 1 :], start=step_start + 1):
        match = re.match(r"^(\s*)-\s+", line)
        if match and len(match.group(1)) <= step_indentation:
            step_end = index
            break

    for index in range(step_start, step_end):
        with_match = re.match(r"^(\s*)with:\s*(?:#.*)?$", lines[index])
        if not with_match or len(with_match.group(1)) != step_key_indentation:
            continue

        input_indentation = None
        for line in lines[index + 1 : step_end]:
            key_match = re.match(r"^(\s*)\S", line)
            if key_match and len(key_match.group(1)) <= step_key_indentation:
                break
            input_match = re.match(r"^(\s*)[A-Za-z0-9_-]+:\s*", line)
            if not input_match:
                continue
            current_indentation = len(input_match.group(1))
            if input_indentation is None:
                input_indentation = current_indentation
            if current_indentation != input_indentation:
                continue
            if re.match(r"^\s*package-manager-cache:\s*false\s*(?:#.*)?$", line):
                return True
    return False


def flow_step_has_cache_disabled(line):
    with_match = FLOW_WITH_PATTERN.search(line)
    return bool(with_match and FLOW_CACHE_PATTERN.search(with_match.group(1)))


def action_has_cache_disabled(lines, start, parsed):
    indentation, list_marker, _, _, flow_mapping = parsed
    if flow_mapping:
        return flow_step_has_cache_disabled(lines[start])
    return step_has_cache_disabled(lines, start, len(indentation), list_marker)


def main():
    failures = parser_failures() + cache_parser_failures()
    discovered = 0

    for path in workflow_files():
        lines = path.read_text().splitlines()
        normalized_lines = [normalize_workflow_line(line) for line in lines]
        for index, line in enumerate(lines):
            parsed = parse_action(line)
            scanned_lines = lines
            candidate_line = line
            if not parsed and PLUGIN_TEMPLATES in path.parents:
                candidate_line = normalized_lines[index]
                parsed = parse_action(candidate_line)
                scanned_lines = normalized_lines
            if not parsed:
                reference = find_action_reference(candidate_line)
                if reference:
                    action, action_ref = reference
                    location = f"{path.relative_to(ROOT)}:{index + 1}"
                    failures.append(
                        f"{location}: unrecognized action step syntax for "
                        f"{action}@{action_ref}"
                    )
                continue

            discovered += 1
            _, _, action, action_ref, _ = parsed
            location = f"{path.relative_to(ROOT)}:{index + 1}"
            if action_ref not in SUPPORTED_REFS[action]:
                failures.append(f"{location}: unsupported {action}@{action_ref}")
            if action == "actions/setup-node" and not action_has_cache_disabled(
                scanned_lines, index, parsed
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
