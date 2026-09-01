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
    r'''^(\s*)(-\s+)?(["']?)uses\3\s*:\s*'''
    r'''(?:(?:&|!)[^\s,\[\]{}]+\s+)*(["']?)'''
    r'''(actions/(?:checkout|setup-go|setup-node))@([^\s,#"']+)\4'''
    r'''(?:\s*(?:#.*)?)$'''
)
ACTION_USES_PATTERN = re.compile(
    r'''(?:^|[\s{,])(["']?)uses\1\s*:\s*'''
    r'''(?:(?:&|!)[^\s,\[\]{}]+\s+)*(["']?)'''
    r'''(actions/(?:checkout|setup-go|setup-node))@([^\s,#}"']+)\2'''
)
USES_ALIAS_PATTERN = re.compile(
    r'''(?:^|[\s{,])(["']?)uses\1\s*:\s*\*[A-Za-z0-9_-]+'''
)
INLINE_WITH_PATTERN = re.compile(
    r'''^(\s*)(["']?)with\2\s*:\s*'''
    r'''(?:(?:&|!)[^\s,\[\]{}]+\s+)*\{([^{}]*)\}\s*(?:#.*)?$'''
)
BLOCK_SCALAR_USES_PATTERN = re.compile(
    r'''^(\s*)(-\s+)?(["']?)uses\3\s*:\s*'''
    r'''(?:(?:&|!)[^\s,\[\]{}]+\s+)*[>|][0-9+-]*\s*(?:#.*)?$'''
)
ACTION_SCALAR_PATTERN = re.compile(
    r'''^(actions/(?:checkout|setup-go|setup-node))@([^\s,#}"']+)$'''
)
ACTION_VALUE_PATTERN = re.compile(
    r'''^(?:(?:&|!)[^\s,\[\]{}]+\s+)*(["']?)'''
    r'''(actions/(?:checkout|setup-go|setup-node))@([^\s,#}"']+)\1$'''
)
FALSE_VALUE_PATTERN = re.compile(
    r'''^(?:(?:&|!)[^\s,\[\]{}]+\s+)*(?:false|"false"|'false')$'''
)


def normalize_workflow_line(line):
    match = re.match(r"^(\s*)# ?(.*)$", line)
    if match:
        return f"{match.group(1)}{match.group(2)}"
    return line


def split_flow_text(value, delimiter):
    parts = []
    start = 0
    depth = 0
    quote = None
    index = 0
    while index < len(value):
        character = value[index]
        if quote:
            if quote == '"' and character == "\\":
                index += 2
                continue
            if quote == "'" and character == "'" and index + 1 < len(value):
                if value[index + 1] == "'":
                    index += 2
                    continue
            if character == quote:
                quote = None
        elif character in "\"'":
            quote = character
        elif character in "[{":
            depth += 1
        elif character in "]}":
            if depth == 0:
                return None
            depth -= 1
        elif character == delimiter and depth == 0:
            parts.append(value[start:index])
            start = index + 1
        index += 1

    if quote or depth:
        return None
    parts.append(value[start:])
    return parts


def flow_key(value):
    value = re.sub(
        r'''^(?:(?:&|!)[^\s,\[\]{}]+\s+)*''', "", value.strip()
    )
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def parse_flow_mapping(value):
    value = value.strip()
    if not value.startswith("{") or not value.endswith("}"):
        return None

    fields = split_flow_text(value[1:-1], ",")
    if fields is None:
        return None
    entries = []
    for field in fields:
        if not field.strip():
            continue
        pair = split_flow_text(field, ":")
        if pair is None or len(pair) < 2:
            return None
        entries.append((flow_key(pair[0]), ":".join(pair[1:]).strip()))
    return entries


def flow_step_mapping(line):
    match = re.match(r"^(\s*)-\s*", line)
    if not match:
        return None

    value = line[match.end() :].strip()
    if not value.startswith("{"):
        return None
    depth = 0
    quote = None
    index = 0
    while index < len(value):
        character = value[index]
        if quote:
            if quote == '"' and character == "\\":
                index += 2
                continue
            if quote == "'" and character == "'" and index + 1 < len(value):
                if value[index + 1] == "'":
                    index += 2
                    continue
            if character == quote:
                quote = None
        elif character in "\"'":
            quote = character
        elif character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                suffix = value[index + 1 :].strip()
                if suffix and not suffix.startswith("#"):
                    return None
                mapping = parse_flow_mapping(value[: index + 1])
                return None if mapping is None else (match.group(1), mapping)
        index += 1
    return None


def flow_mapping_value(entries, key):
    for entry_key, value in entries:
        if entry_key == key:
            return value
    return None


def parse_action(line):
    match = BLOCK_ACTION_PATTERN.match(line)
    if match:
        indentation, list_marker, _, _, action, action_ref = match.groups()
        return indentation, bool(list_marker), action, action_ref, False

    flow_step = flow_step_mapping(line)
    if flow_step:
        indentation, entries = flow_step
        uses_value = flow_mapping_value(entries, "uses")
        match = None if uses_value is None else ACTION_VALUE_PATTERN.match(uses_value)
        if match:
            _, action, action_ref = match.groups()
            return indentation, True, action, action_ref, True

    return None


def find_action_reference(line):
    match = ACTION_USES_PATTERN.search(line)
    return None if match is None else (match.group(3), match.group(4))


def parse_block_scalar_action(lines, start):
    match = BLOCK_SCALAR_USES_PATTERN.match(lines[start])
    if not match:
        return None

    indentation, list_marker, _ = match.groups()
    key_indentation = len(indentation) + (2 if list_marker else 0)
    content = []
    for line in lines[start + 1 :]:
        if not line.strip():
            continue
        content_match = re.match(r"^(\s*)(.*)$", line)
        if len(content_match.group(1)) <= key_indentation:
            break
        content.append(content_match.group(2).strip())

    if len(content) != 1:
        return None
    action_match = ACTION_SCALAR_PATTERN.match(content[0])
    if not action_match:
        return None
    action, action_ref = action_match.groups()
    return indentation, bool(list_marker), action, action_ref, False


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
        "      - uses: &checkout actions/checkout@v4": (
            "actions/checkout",
            "v4",
        ),
        "      - uses: !!str actions/setup-go@v6": ("actions/setup-go", "v6"),
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
    if not USES_ALIAS_PATTERN.search("      - uses: *checkout"):
        failures.append("action fallback missed alias fixture")
    nested_flow_line = (
        '      - { run: echo "$uses", env: { uses: actions/checkout@v4 } }'
    )
    if parse_action(nested_flow_line) is not None:
        failures.append("action parser accepted nested flow uses fixture")
    nested_flow_step = flow_step_mapping(nested_flow_line)
    if nested_flow_step is None or flow_mapping_value(nested_flow_step[1], "uses"):
        failures.append("flow parser promoted nested uses fixture")
    quoted_flow_line = (
        "      - { run: 'echo uses: actions/checkout@v4', name: Example }"
    )
    if parse_action(quoted_flow_line) is not None:
        failures.append("action parser accepted quoted flow uses fixture")
    quoted_flow_step = flow_step_mapping(quoted_flow_line)
    if quoted_flow_step is None or flow_mapping_value(quoted_flow_step[1], "uses"):
        failures.append("flow parser promoted quoted uses fixture")
    block_scalar_lines = [
        "      - uses: >-",
        "          actions/checkout@v4",
    ]
    block_scalar_action = parse_block_scalar_action(block_scalar_lines, 0)
    if block_scalar_action is None or block_scalar_action[2:4] != (
        "actions/checkout",
        "v4",
    ):
        failures.append("action parser missed block scalar fixture")
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
                '        "with":',
                '          "package-manager-cache": "false"',
                '        "uses": actions/setup-node@v7',
            ],
            3,
            True,
        ),
        (
            [
                "      - name: Set up Node",
                "        with: &inputs",
                "          package-manager-cache: &disabled false",
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
        (
            [
                "      - uses: &setup-node actions/setup-node@v7",
                "        with: { package-manager-cache: false }",
            ],
            0,
            True,
        ),
        (
            [
                "      - uses: >-",
                "          actions/setup-node@v7",
                "        with:",
                "          package-manager-cache: false",
            ],
            0,
            True,
        ),
    )
    failures = []
    for lines, uses_index, expected in cases:
        parsed = parse_action(lines[uses_index]) or parse_block_scalar_action(
            lines, uses_index
        )
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
        inline_with_match = INLINE_WITH_PATTERN.match(lines[index])
        if (
            inline_with_match
            and len(inline_with_match.group(1)) == step_key_indentation
        ):
            return flow_mapping_has_cache_disabled(
                f"{{{inline_with_match.group(3)}}}"
            )

        with_match = re.match(
            r'''^(\s*)(["']?)with\2\s*:\s*'''
            r'''(?:(?:&|!)[^\s,\[\]{}]+\s*)*(?:#.*)?$''',
            lines[index],
        )
        if not with_match or len(with_match.group(1)) != step_key_indentation:
            continue

        input_indentation = None
        for line in lines[index + 1 : step_end]:
            key_match = re.match(r"^(\s*)\S", line)
            if key_match and len(key_match.group(1)) <= step_key_indentation:
                break
            input_match = re.match(
                r'''^(\s*)(["']?)[A-Za-z0-9_-]+\2\s*:\s*''', line
            )
            if not input_match:
                continue
            current_indentation = len(input_match.group(1))
            if input_indentation is None:
                input_indentation = current_indentation
            if current_indentation != input_indentation:
                continue
            if re.match(
                r'''^\s*(["']?)package-manager-cache\1\s*:\s*'''
                r'''(?:(?:&|!)[^\s,\[\]{}]+\s+)*'''
                r'''(?:false|"false"|'false')\s*(?:#.*)?$''',
                line,
            ):
                return True
    return False


def flow_step_has_cache_disabled(line):
    flow_step = flow_step_mapping(line)
    if not flow_step:
        return False
    with_value = flow_mapping_value(flow_step[1], "with")
    return bool(with_value and flow_mapping_has_cache_disabled(with_value))


def flow_mapping_has_cache_disabled(value):
    entries = parse_flow_mapping(value)
    if entries is None:
        return False
    cache_value = flow_mapping_value(entries, "package-manager-cache")
    return bool(cache_value and FALSE_VALUE_PATTERN.match(cache_value))


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
            parsed = parse_action(line) or parse_block_scalar_action(lines, index)
            scanned_lines = lines
            candidate_line = line
            if not parsed and PLUGIN_TEMPLATES in path.parents:
                candidate_line = normalized_lines[index]
                parsed = parse_action(candidate_line) or parse_block_scalar_action(
                    normalized_lines, index
                )
                scanned_lines = normalized_lines
            if not parsed:
                flow_step = flow_step_mapping(candidate_line)
                fallback_line = candidate_line
                if flow_step:
                    uses_value = flow_mapping_value(flow_step[1], "uses")
                    if uses_value is None:
                        continue
                    fallback_line = f"uses: {uses_value}"
                reference = find_action_reference(fallback_line)
                if reference:
                    action, action_ref = reference
                    location = f"{path.relative_to(ROOT)}:{index + 1}"
                    failures.append(
                        f"{location}: unrecognized action step syntax for "
                        f"{action}@{action_ref}"
                    )
                elif USES_ALIAS_PATTERN.search(fallback_line):
                    location = f"{path.relative_to(ROOT)}:{index + 1}"
                    failures.append(f"{location}: action aliases are not supported")
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
