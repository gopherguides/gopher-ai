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
    r'''(?:\s*(?:#.*)?)$''',
    re.IGNORECASE,
)
BLOCK_USES_KEY_PATTERN = re.compile(
    r'''^(\s*)(-\s+)?(?:(?:&|!)[^\s,\[\]{}]+\s+)*'''
    r'''(["']?)uses\3\s*:'''
)
ACTION_USES_PATTERN = re.compile(
    r'''(?:^|[\s{,])(["']?)uses\1\s*:\s*'''
    r'''(?:(?:&|!)[^\s,\[\]{}]+\s+)*(["']?)'''
    r'''(actions/(?:checkout|setup-go|setup-node))@([^\s,#}"']+)\2''',
    re.IGNORECASE,
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
EXPLICIT_USES_PATTERN = re.compile(
    r'''^(\s*)(-\s+)?\?\s*'''
    r'''(?:(?:&|!)[^\s,\[\]{}]+\s+)*(["']?)uses\3\s*(?:#.*)?$'''
)
ACTION_SCALAR_PATTERN = re.compile(
    r'''^(actions/(?:checkout|setup-go|setup-node))@([^\s,#}"']+)$''',
    re.IGNORECASE,
)
FALSE_VALUE_PATTERN = re.compile(
    r'''^(?:(?:&|!)[^\s,\[\]{}]+\s+)*(?:false|"false"|'false')$'''
)
LIST_ITEM_PATTERN = re.compile(r"^(\s*)-(?:\s+|$)")
SCALAR_PREFIX_PATTERN = re.compile(
    r'''^(?:(?:&|!)[^\s,\[\]{}]+\s+)*'''
)
DOUBLE_QUOTED_ESCAPES = {
    "0": "\0",
    "a": "\a",
    "b": "\b",
    "t": "\t",
    "n": "\n",
    "v": "\v",
    "f": "\f",
    "r": "\r",
    "e": "\x1b",
    " ": " ",
    '"': '"',
    "/": "/",
    "\\": "\\",
    "N": "\x85",
    "_": "\xa0",
    "L": "\u2028",
    "P": "\u2029",
}


def normalize_workflow_line(line):
    match = re.match(r"^(\s*)# ?(.*)$", line)
    if match:
        return f"{match.group(1)}{match.group(2)}"
    return line


def decode_double_quoted_scalar(value):
    decoded = []
    index = 1
    while index < len(value):
        character = value[index]
        if character == '"':
            suffix = value[index + 1 :].strip()
            if suffix and not suffix.startswith("#"):
                return None
            return "".join(decoded)
        if character != "\\":
            decoded.append(character)
            index += 1
            continue
        index += 1
        if index >= len(value):
            return None
        escape = value[index]
        if escape in DOUBLE_QUOTED_ESCAPES:
            decoded.append(DOUBLE_QUOTED_ESCAPES[escape])
            index += 1
            continue
        lengths = {"x": 2, "u": 4, "U": 8}
        length = lengths.get(escape)
        if length is None:
            return None
        digits = value[index + 1 : index + 1 + length]
        if len(digits) != length or not re.fullmatch(r"[0-9A-Fa-f]+", digits):
            return None
        try:
            decoded.append(chr(int(digits, 16)))
        except ValueError:
            return None
        index += length + 1
    return None


def decode_single_quoted_scalar(value):
    decoded = []
    index = 1
    while index < len(value):
        character = value[index]
        if character != "'":
            decoded.append(character)
            index += 1
            continue
        if index + 1 < len(value) and value[index + 1] == "'":
            decoded.append("'")
            index += 2
            continue
        suffix = value[index + 1 :].strip()
        if suffix and not suffix.startswith("#"):
            return None
        return "".join(decoded)
    return None


def decode_yaml_scalar(value):
    value = SCALAR_PREFIX_PATTERN.sub("", value.strip(), count=1)
    if not value:
        return None
    if value.startswith('"'):
        return decode_double_quoted_scalar(value)
    if value.startswith("'"):
        return decode_single_quoted_scalar(value)
    return re.split(r"\s+#", value, maxsplit=1)[0].rstrip()


def parse_action_value(value):
    scalar = decode_yaml_scalar(value)
    if scalar is None:
        return None
    match = ACTION_SCALAR_PATTERN.match(scalar)
    if not match:
        return None
    action, action_ref = match.groups()
    return action.lower(), action_ref


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


def enclosing_steps_index(lines, start):
    for candidate in range(start - 1, -1, -1):
        match = re.match(
            r'''^(\s*)(?:(?:&|!)[^\s,\[\]{}]+\s+)*'''
            r'''(["']?)steps\2\s*:\s*'''
            r'''(?:(?:&|!)[^\s,\[\]{}]+\s*)*(?:#.*)?$''',
            lines[candidate],
        )
        if not match:
            continue
        steps_indentation = len(match.group(1))
        enclosed = True
        for line in lines[candidate + 1 : start + 1]:
            if not line.strip():
                continue
            indentation = len(line) - len(line.lstrip())
            if indentation < steps_indentation:
                enclosed = False
                break
            if indentation == steps_indentation and not LIST_ITEM_PATTERN.match(line):
                enclosed = False
                break
        if enclosed:
            return candidate
    return None


def action_is_step_key(lines, start, parsed):
    steps_index = enclosing_steps_index(lines, start)
    if steps_index is None:
        return False

    steps_indentation = len(lines[steps_index]) - len(lines[steps_index].lstrip())
    list_indents = []
    for line in lines[steps_index + 1 : start + 1]:
        match = LIST_ITEM_PATTERN.match(line)
        if match and len(match.group(1)) >= steps_indentation:
            list_indents.append(len(match.group(1)))
    if not list_indents:
        return False

    indentation, list_marker, _, _, _ = parsed
    step_indentation = min(list_indents)
    action_indentation = len(indentation)
    if list_marker:
        return action_indentation == step_indentation
    return action_indentation == step_indentation + 2


def parse_action(line):
    match = BLOCK_ACTION_PATTERN.match(line)
    if match:
        indentation, list_marker, _, _, action, action_ref = match.groups()
        return indentation, bool(list_marker), action.lower(), action_ref, False

    flow_step = flow_step_mapping(line)
    if flow_step:
        indentation, entries = flow_step
        uses_value = flow_mapping_value(entries, "uses")
        parsed_value = None if uses_value is None else parse_action_value(uses_value)
        if parsed_value:
            action, action_ref = parsed_value
            return indentation, True, action, action_ref, True

    uses_context = block_uses_context(line)
    if uses_context:
        match = BLOCK_USES_KEY_PATTERN.match(line)
        parsed_value = parse_action_value(line[match.end() :])
        if parsed_value:
            action, action_ref = parsed_value
            indentation, list_marker, _, _, _ = uses_context
            return indentation, list_marker, action, action_ref, False

    return None


def block_uses_context(line):
    match = BLOCK_USES_KEY_PATTERN.match(line)
    if not match:
        return None
    indentation, list_marker, _ = match.groups()
    return indentation, bool(list_marker), "", "", False


def find_action_reference(line):
    match = ACTION_USES_PATTERN.search(line)
    return None if match is None else (match.group(3).lower(), match.group(4))


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
    return indentation, bool(list_marker), action.lower(), action_ref, False


def explicit_uses_value(lines, start):
    match = EXPLICIT_USES_PATTERN.match(lines[start])
    if not match:
        return None

    indentation, list_marker, _ = match.groups()
    value_indentation = len(indentation) + (2 if list_marker else 0)
    for index in range(start + 1, len(lines)):
        if not lines[index].strip():
            continue
        value_match = re.match(r"^(\s*):\s*(.*)$", lines[index])
        if not value_match or len(value_match.group(1)) != value_indentation:
            return None
        value = value_match.group(2).strip()
        if re.match(
            r'''^(?:(?:&|!)[^\s,\[\]{}]+\s+)*[>|][0-9+-]*''', value
        ):
            content = []
            for content_line in lines[index + 1 :]:
                if not content_line.strip():
                    continue
                content_match = re.match(r"^(\s*)(.*)$", content_line)
                if len(content_match.group(1)) <= value_indentation:
                    break
                content.append(content_match.group(2).strip())
            if len(content) != 1:
                return None
            value = content[0]
        return indentation, bool(list_marker), value
    return None


def parse_explicit_action(lines, start):
    explicit_value = explicit_uses_value(lines, start)
    if not explicit_value:
        return None
    indentation, list_marker, value = explicit_value
    parsed_value = parse_action_value(value)
    if not parsed_value:
        return None
    action, action_ref = parsed_value
    return indentation, list_marker, action, action_ref, False


def unparsed_action_reference(lines, start, line):
    explicit_value = explicit_uses_value(lines, start)
    if explicit_value:
        indentation, list_marker, value = explicit_value
        uses_context = indentation, list_marker, "", "", False
        if not action_is_step_key(lines, start, uses_context):
            return None
        fallback_line = f"uses: {value}"
    else:
        flow_step = flow_step_mapping(line)
        if flow_step:
            uses_value = flow_mapping_value(flow_step[1], "uses")
            if uses_value is None:
                return None
            fallback_line = f"uses: {uses_value}"
        else:
            uses_context = block_uses_context(line)
            if not uses_context or not action_is_step_key(
                lines, start, uses_context
            ):
                return None
            fallback_line = line

    reference = find_action_reference(fallback_line)
    if reference:
        return "reference", reference
    if USES_ALIAS_PATTERN.search(fallback_line):
        return "alias", None
    return None


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
        "      - uses: Actions/Checkout@v4": ("actions/checkout", "v4"),
        "      - uses: actions/Setup-Node@v4": ("actions/setup-node", "v4"),
        "  #     - uses: actions/setup-go@v6": ("actions/setup-go", "v6"),
        "      - { uses: actions/checkout@v4 }": ("actions/checkout", "v4"),
        '      - { name: Checkout, "uses": "actions/checkout@v4" }': (
            "actions/checkout",
            "v4",
        ),
        r'      - uses: "actions\u002fcheckout@v4"': (
            "actions/checkout",
            "v4",
        ),
        r'      - { uses: "actions\x2fsetup-go@v6" }': (
            "actions/setup-go",
            "v6",
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
    unrecognized_lines = [
        "    steps:",
        "      - name: Checkout",
        "        uses: actions/checkout@v4,",
    ]
    if unparsed_action_reference(
        unrecognized_lines, 2, unrecognized_lines[2]
    ) != ("reference", ("actions/checkout", "v4")):
        failures.append("action fallback missed direct step fixture")
    noise_lines = [
        "    steps:",
        "      - run: echo uses: actions/checkout@v4",
        "      # old example uses: actions/checkout@v4",
    ]
    for index in range(1, len(noise_lines)):
        if unparsed_action_reference(noise_lines, index, noise_lines[index]):
            failures.append("action fallback promoted non-step text fixture")
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
    block_lines = [
        "    steps:",
        "      - name: Example",
        "        env:",
        "          uses: actions/checkout@v4",
        "        uses: actions/checkout@v7",
    ]
    nested_action = parse_action(block_lines[3])
    direct_action = parse_action(block_lines[4])
    if nested_action is None or action_is_step_key(block_lines, 3, nested_action):
        failures.append("action parser promoted nested block uses fixture")
    if direct_action is None or not action_is_step_key(block_lines, 4, direct_action):
        failures.append("action parser missed direct block uses fixture")
    nested_alias = block_uses_context("          uses: *checkout")
    if nested_alias is None or action_is_step_key(block_lines, 3, nested_alias):
        failures.append("action parser promoted nested block alias fixture")
    bare_item_lines = [
        "    steps:",
        "      -",
        "        uses: actions/checkout@v4",
    ]
    bare_item_action = parse_action(bare_item_lines[2])
    if bare_item_action is None or not action_is_step_key(
        bare_item_lines, 2, bare_item_action
    ):
        failures.append("action parser missed bare sequence fixture")
    explicit_lines = [
        "    steps:",
        "      - ? uses",
        "        : actions/checkout@v4",
    ]
    explicit_action = parse_explicit_action(explicit_lines, 1)
    if explicit_action is None or explicit_action[2:4] != (
        "actions/checkout",
        "v4",
    ):
        failures.append("action parser missed explicit key fixture")
    elif not action_is_step_key(explicit_lines, 1, explicit_action):
        failures.append("action parser misplaced explicit key fixture")
    explicit_scalar_lines = [
        "    steps:",
        "      - ? uses",
        "        : >-",
        "            actions/checkout@v4",
    ]
    explicit_scalar_action = parse_explicit_action(explicit_scalar_lines, 1)
    if explicit_scalar_action is None or explicit_scalar_action[2:4] != (
        "actions/checkout",
        "v4",
    ):
        failures.append("action parser missed explicit scalar fixture")
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
                "      -",
                "        uses: actions/setup-node@v7",
                "        with:",
                "          package-manager-cache: false",
            ],
            1,
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
        (
            [
                "      - ? uses",
                "        : actions/setup-node@v7",
                "        with:",
                "          package-manager-cache: false",
            ],
            0,
            True,
        ),
    )
    failures = []
    for lines, uses_index, expected in cases:
        parsed = (
            parse_action(lines[uses_index])
            or parse_block_scalar_action(lines, uses_index)
            or parse_explicit_action(lines, uses_index)
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
            match = LIST_ITEM_PATTERN.match(lines[index])
            if match and len(match.group(1)) < indentation:
                step_start = index
                step_indentation = len(match.group(1))
                break

    step_end = len(lines)
    for index, line in enumerate(lines[step_start + 1 :], start=step_start + 1):
        match = LIST_ITEM_PATTERN.match(line)
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
            parsed = (
                parse_action(line)
                or parse_block_scalar_action(lines, index)
                or parse_explicit_action(lines, index)
            )
            scanned_lines = lines
            candidate_line = line
            if not parsed and PLUGIN_TEMPLATES in path.parents:
                candidate_line = normalized_lines[index]
                parsed = (
                    parse_action(candidate_line)
                    or parse_block_scalar_action(normalized_lines, index)
                    or parse_explicit_action(normalized_lines, index)
                )
                scanned_lines = normalized_lines
            if not parsed:
                unparsed = unparsed_action_reference(
                    scanned_lines, index, candidate_line
                )
                if unparsed and unparsed[0] == "reference":
                    action, action_ref = unparsed[1]
                    location = f"{path.relative_to(ROOT)}:{index + 1}"
                    failures.append(
                        f"{location}: unrecognized action step syntax for "
                        f"{action}@{action_ref}"
                    )
                elif unparsed and unparsed[0] == "alias":
                    location = f"{path.relative_to(ROOT)}:{index + 1}"
                    failures.append(f"{location}: action aliases are not supported")
                continue

            if not action_is_step_key(scanned_lines, index, parsed):
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
