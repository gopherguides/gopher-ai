#!/usr/bin/env python3

import pathlib
import re
import sys

try:
    import yaml
except ModuleNotFoundError:
    print(
        "PyYAML is required; install requirements-test.txt",
        file=sys.stderr,
    )
    raise SystemExit(2)


ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"
COMPOSITE_ACTIONS = ROOT / ".github" / "actions"
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
    r'''(?:\s+#.*)?\s*$''',
    re.IGNORECASE,
)
ACTION_USES_PATTERN = re.compile(
    r'''(?:^|[\s{,])(["']?)uses\1\s*:\s*'''
    r'''(?:(?:&|!)[^\s,\[\]{}]+\s+)*(["']?)'''
    r'''(actions/(?:checkout|setup-go|setup-node))@([^\s,#}"']+)\2''',
    re.IGNORECASE,
)
USES_ALIAS_PATTERN = re.compile(
    r'''(?:^|[\s{,])(["']?)uses\1\s*:\s*\*[^\s,\[\]{}]+'''
)
STEP_ALIAS_PATTERN = re.compile(
    r'''^(\s*)-\s*(?:(?:&|!)[^\s,\[\]{}]+\s+)*'''
    r'''\*[^\s,\[\]{}]+\s*(?:#.*)?$'''
)
YAML_ALIAS_PATTERN = re.compile(r'''^\*[^\s,\[\]{}]+\s*(?:#.*)?$''')
ACTION_SCALAR_PATTERN = re.compile(
    r'''^(actions/(?:checkout|setup-go|setup-node))@([^\s,#}"']+)$''',
    re.IGNORECASE,
)
LIST_ITEM_PATTERN = re.compile(r"^(\s*)-(?:\s+|$)")
SCALAR_PREFIX_PATTERN = re.compile(
    r'''^(?:(?:&|!)[^\s,\[\]{}]+(?:\s+|$))*'''
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


def scalar_is_false(value):
    scalar = decode_yaml_scalar(value)
    return scalar is not None and scalar.casefold() == "false"


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


def strip_yaml_comment(value):
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
        elif character == "#" and (index == 0 or value[index - 1].isspace()):
            return value[:index].rstrip()
        index += 1
    return value.rstrip()


def joined_flow_step(lines, start):
    match = re.match(r"^(\s*)-\s*", lines[start])
    if not match:
        return None
    value = SCALAR_PREFIX_PATTERN.sub(
        "", lines[start][match.end() :].lstrip(), count=1
    )
    if not value.startswith("{"):
        return None

    fragments = []
    depth = 0
    quote = None
    for index in range(start, len(lines)):
        fragment = strip_yaml_comment(lines[index])
        fragments.append(fragment.rstrip() if index == start else fragment.strip())
        character_index = 0
        while character_index < len(fragment):
            character = fragment[character_index]
            if quote:
                if quote == '"' and character == "\\":
                    character_index += 2
                    continue
                if (
                    quote == "'"
                    and character == "'"
                    and character_index + 1 < len(fragment)
                    and fragment[character_index + 1] == "'"
                ):
                    character_index += 2
                    continue
                if character == quote:
                    quote = None
            elif character in "\"'":
                quote = character
            elif character in "[{":
                depth += 1
            elif character in "]}":
                depth -= 1
                if depth < 0:
                    return None
            character_index += 1
        if depth == 0 and quote is None:
            return " ".join(part for part in fragments if part), index
    return None


def flow_step_lines(lines):
    joined = {}
    continuations = set()
    for start in range(len(lines)):
        if start in continuations:
            continue
        result = joined_flow_step(lines, start)
        if not result:
            continue
        line, end = result
        joined[start] = line
        continuations.update(range(start + 1, end + 1))
    return joined, continuations


def flow_key(value):
    decoded = decode_yaml_scalar(value)
    return value.strip() if decoded is None else decoded


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

    value = SCALAR_PREFIX_PATTERN.sub(
        "", line[match.end() :].strip(), count=1
    )
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


def block_mapping_entry(line):
    match = re.match(r"^(\s*)(-\s+)?(.*)$", line)
    if not match:
        return None
    indentation, list_marker, body = match.groups()
    pair = split_flow_text(body, ":")
    if pair is None or len(pair) < 2:
        return None
    key = decode_yaml_scalar(pair[0])
    if key is None:
        return None
    return indentation, bool(list_marker), key, ":".join(pair[1:]).strip()


def explicit_mapping_key_context(line):
    match = re.match(r"^(\s*)(-\s+)?\?\s*(.*)$", line)
    if not match:
        return None
    indentation, list_marker, key_value = match.groups()
    key = decode_yaml_scalar(key_value)
    if key is None:
        return None
    return indentation, bool(list_marker), key


def is_block_scalar_value(value):
    value = SCALAR_PREFIX_PATTERN.sub("", value.strip(), count=1)
    return bool(re.fullmatch(r"[>|][0-9+-]*\s*(?:#.*)?", value))


def block_scalar_header_indentation(line):
    entry = block_mapping_entry(line)
    if entry and is_block_scalar_value(entry[3]):
        return len(entry[0]) + (2 if entry[1] else 0)

    match = re.match(r"^(\s*)-\s*(.*)$", line)
    if match and is_block_scalar_value(match.group(2)):
        return len(match.group(1))

    match = re.match(r"^(\s*):\s*(.*)$", line)
    if match and is_block_scalar_value(match.group(2)):
        return len(match.group(1))
    return None


def block_scalar_content_indices(lines):
    content_indices = set()
    header_indentation = None
    for index, line in enumerate(lines):
        if header_indentation is not None:
            if not line.strip():
                content_indices.add(index)
                continue
            indentation = len(line) - len(line.lstrip())
            if indentation > header_indentation:
                content_indices.add(index)
                continue
            header_indentation = None

        header_indentation = block_scalar_header_indentation(line)
    return content_indices


def block_scalar_value(lines, start, key_indentation):
    content = []
    for line in lines[start + 1 :]:
        if not line.strip():
            content.append("")
            continue
        indentation = len(line) - len(line.lstrip())
        if indentation <= key_indentation:
            break
        content.append(line)
    nonempty_indents = [
        len(line) - len(line.lstrip()) for line in content if line.strip()
    ]
    if not nonempty_indents:
        return None
    content_indentation = min(nonempty_indents)
    values = [line[content_indentation:] if line else "" for line in content]
    return " ".join(value.strip() for value in values).strip()


def enclosing_steps_index(lines, start):
    scalar_content = block_scalar_content_indices(lines)
    for candidate in range(start - 1, -1, -1):
        if candidate in scalar_content:
            continue
        entry = block_mapping_entry(lines[candidate])
        if not entry or entry[1] or entry[2] != "steps":
            continue
        value = SCALAR_PREFIX_PATTERN.sub("", entry[3], count=1).strip()
        if value and not value.startswith("#"):
            continue
        steps_indentation = len(entry[0])
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
            return indentation, True, action, action_ref, line

    uses_context = block_uses_context(line)
    if uses_context:
        parsed_value = parse_action_value(block_mapping_entry(line)[3])
        if parsed_value:
            action, action_ref = parsed_value
            indentation, list_marker, _, _, _ = uses_context
            return indentation, list_marker, action, action_ref, False

    return None


def block_uses_context(line):
    entry = block_mapping_entry(line)
    if not entry or entry[2] != "uses":
        return None
    indentation, list_marker, _, _ = entry
    return indentation, list_marker, "", "", False


def step_alias_context(line):
    match = STEP_ALIAS_PATTERN.match(line)
    if not match:
        return None
    return match.group(1), True, "", "", False


def find_action_reference(line):
    match = ACTION_USES_PATTERN.search(line)
    return None if match is None else (match.group(3).lower(), match.group(4))


def parse_block_scalar_action(lines, start):
    entry = block_mapping_entry(lines[start])
    if not entry or entry[2] != "uses" or not is_block_scalar_value(entry[3]):
        return None

    indentation, list_marker, _, _ = entry
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
    return indentation, list_marker, action.lower(), action_ref, False


def explicit_uses_value(lines, start):
    context = explicit_mapping_key_context(lines[start])
    if not context or context[2] != "uses":
        return None

    indentation, list_marker, _ = context
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
        return indentation, list_marker, value
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
    alias_context = step_alias_context(line)
    if alias_context and action_is_step_key(lines, start, alias_context):
        return "alias", None

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
        "      - &checkout { uses: actions/checkout@v4 }": (
            "actions/checkout",
            "v4",
        ),
        "      - !!map { uses: actions/setup-go@v6 }": (
            "actions/setup-go",
            "v6",
        ),
        r'      - uses: "actions\u002fcheckout@v4"': (
            "actions/checkout",
            "v4",
        ),
        r'      - { uses: "actions\x2fsetup-go@v6" }': (
            "actions/setup-go",
            "v6",
        ),
        r'      - "\u0075ses": actions/checkout@v4': (
            "actions/checkout",
            "v4",
        ),
        r'      - { "\u0075ses": actions/setup-go@v6 }': (
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
    attached_hash_lines = [
        "    steps:",
        "      - uses: actions/checkout@v7#bogus",
    ]
    if parse_action(attached_hash_lines[1]) is not None:
        failures.append("action parser treated attached hash as a comment")
    if unparsed_action_reference(
        attached_hash_lines, 1, attached_hash_lines[1]
    ) != ("reference", ("actions/checkout", "v7")):
        failures.append("action fallback missed attached hash fixture")
    if not USES_ALIAS_PATTERN.search("      - uses: *checkout"):
        failures.append("action fallback missed alias fixture")
    step_alias_lines = [
        "env: &checkout { uses: actions/checkout@v4 }",
        "jobs:",
        "  test:",
        "    steps:",
        "      - *checkout",
    ]
    if unparsed_action_reference(
        step_alias_lines, 4, step_alias_lines[4]
    ) != ("alias", None):
        failures.append("action fallback missed whole-step alias fixture")
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
    block_scalar_lines = [
        "    steps:",
        "      - run: |",
        "          cat <<'EOF'",
        "          steps:",
        "            - uses: actions/checkout@v4",
        "          EOF",
        "      - uses: actions/checkout@v7",
    ]
    scalar_content = block_scalar_content_indices(block_scalar_lines)
    if 4 not in scalar_content or 6 in scalar_content:
        failures.append("block scalar boundary parser failed fixture")
    step_scalar_lines = [
        "    steps:",
        "      - name: |",
        "          Checkout repository",
        "        uses: actions/checkout@v4",
    ]
    scalar_content = block_scalar_content_indices(step_scalar_lines)
    if 2 not in scalar_content or 3 in scalar_content:
        failures.append("step scalar boundary parser failed fixture")
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
    multiline_flow_lines = [
        "    steps:",
        "      - &checkout {",
        "          name: Checkout,",
        "          uses: actions/checkout@v4",
        "        }",
    ]
    joined_flow = joined_flow_step(multiline_flow_lines, 1)
    multiline_action = None if joined_flow is None else parse_action(joined_flow[0])
    if multiline_action is None or multiline_action[2:4] != (
        "actions/checkout",
        "v4",
    ):
        failures.append("action parser missed multiline flow fixture")
    elif not action_is_step_key(multiline_flow_lines, 1, multiline_action):
        failures.append("action parser misplaced multiline flow fixture")
    _, multiline_continuations = flow_step_lines(multiline_flow_lines)
    if multiline_continuations != {2, 3, 4}:
        failures.append("flow parser missed multiline continuation fixture")
    flow_steps_lines = [
        "jobs:",
        "  test:",
        "    steps: [ { uses: actions/checkout@v4 } ]",
    ]
    if unsupported_steps_collections(flow_steps_lines) != [2]:
        failures.append("policy missed flow-style steps collection fixture")
    alias_steps_lines = [
        "jobs:",
        "  test:",
        "    steps: *shared-steps",
    ]
    if unsupported_steps_collections(alias_steps_lines) != [2]:
        failures.append("policy missed aliased steps collection fixture")
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
    escaped_explicit_lines = [
        "    steps:",
        r'      - ? "\u0075ses"',
        "        : actions/checkout@v4",
    ]
    escaped_explicit_action = parse_explicit_action(escaped_explicit_lines, 1)
    if escaped_explicit_action is None or escaped_explicit_action[2:4] != (
        "actions/checkout",
        "v4",
    ):
        failures.append("action parser missed escaped explicit key fixture")
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
                "      - uses: actions/setup-node@v7",
                "        with:",
                "          package-manager-cache: FALSE",
            ],
            0,
            True,
        ),
        (
            [
                "      - uses: actions/setup-node@v7",
                "        with:",
                "          package-manager-cache: >-",
                "            false",
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
                r'        "\u0077ith":',
                r'          "package-manager-\u0063ache": False',
                "        uses: actions/setup-node@v7",
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
                "        with:",
                "          package-manager-cache: false#bogus",
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
                "      - { uses: actions/setup-node@v7, with: { package-manager-cache: 'False' } }",
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
                "        with: { package-manager-cache: false } # disable caching",
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
    multiline_flow_lines = [
        "    steps:",
        "      - {",
        "          uses: actions/setup-node@v7,",
        "          with: { package-manager-cache: false }",
        "        }",
    ]
    joined_flow = joined_flow_step(multiline_flow_lines, 1)
    parsed = None if joined_flow is None else parse_action(joined_flow[0])
    if parsed is None or not action_has_cache_disabled(
        multiline_flow_lines, 1, parsed
    ):
        failures.append("cache parser missed multiline flow fixture")
    alias_lines = [
        "      - uses: actions/setup-node@v7",
        "        with: *node-inputs",
    ]
    parsed = parse_action(alias_lines[0])
    if action_cache_status(alias_lines, 0, parsed) != "alias":
        failures.append("cache parser missed block input alias fixture")
    flow_alias_line = "      - { uses: actions/setup-node@v7, with: *node-inputs }"
    parsed = parse_action(flow_alias_line)
    if action_cache_status([flow_alias_line], 0, parsed) != "alias":
        failures.append("cache parser missed flow input alias fixture")
    return failures


def workflow_files():
    return sorted(
        (
            *WORKFLOWS.glob("*.yml"),
            *WORKFLOWS.glob("*.yaml"),
            *COMPOSITE_ACTIONS.glob("**/action.yml"),
            *COMPOSITE_ACTIONS.glob("**/action.yaml"),
            *PLUGIN_TEMPLATES.glob("*/templates/**/*.yml"),
            *PLUGIN_TEMPLATES.glob("*/templates/**/*.yaml"),
            *AGENT_SKILLS.glob("**/*.md"),
        )
    )


def coverage_failures():
    composite_manifests = {
        *COMPOSITE_ACTIONS.glob("**/action.yml"),
        *COMPOSITE_ACTIONS.glob("**/action.yaml"),
    }
    missing = composite_manifests.difference(workflow_files())
    return [
        f"composite action manifest is not scanned: {path.relative_to(ROOT)}"
        for path in sorted(missing)
    ]


def dependency_callsite_failures():
    callers = (
        ROOT / "detent.yaml",
        ROOT / "plugins" / "productivity" / "commands" / "release.md",
    )
    failures = []
    for path in callers:
        command_lines = [
            line for line in path.read_text().splitlines() if "test-commands.sh" in line
        ]
        if not command_lines or any(
            "requirements-test.txt" not in line for line in command_lines
        ):
            failures.append(
                f"test dependency is not provisioned by {path.relative_to(ROOT)}"
            )
    return failures


def yaml_mapping_values(node, key):
    if not isinstance(node, yaml.MappingNode):
        return []
    return [
        value
        for candidate, value in node.value
        if isinstance(candidate, yaml.ScalarNode) and candidate.value == key
    ]


def yaml_scalar_is_false(node):
    return isinstance(node, yaml.ScalarNode) and node.value.strip().casefold() == "false"


def scan_yaml_action_step(path, step):
    failures = []
    discovered = 0
    for uses_node in yaml_mapping_values(step, "uses"):
        if not isinstance(uses_node, yaml.ScalarNode):
            continue
        uses_value = uses_node.value.strip()
        match = re.fullmatch(
            r"(actions/(?:checkout|setup-go|setup-node))@(.+)",
            uses_value,
            re.IGNORECASE,
        )
        if not match:
            continue
        action, action_ref = match.groups()
        action = action.lower()
        discovered += 1
        location = f"{path.relative_to(ROOT)}:{uses_node.start_mark.line + 1}"
        if action_ref not in SUPPORTED_REFS[action]:
            failures.append(f"{location}: unsupported {action}@{action_ref}")
        if action != "actions/setup-node":
            continue
        cache_disabled = False
        for with_node in yaml_mapping_values(step, "with"):
            for cache_node in yaml_mapping_values(
                with_node, "package-manager-cache"
            ):
                cache_disabled = cache_disabled or yaml_scalar_is_false(cache_node)
        if not cache_disabled:
            failures.append(
                f"{location}: setup-node must set package-manager-cache: false"
            )
    return failures, discovered


def scan_parsed_yaml(path, source=None):
    try:
        root = yaml.compose(path.read_text() if source is None else source)
    except yaml.YAMLError as error:
        return [f"{path.relative_to(ROOT)}: invalid YAML: {error}"], 0
    if root is None:
        return [], 0

    failures = []
    discovered = 0
    step_collections = []
    if WORKFLOWS in path.parents:
        for jobs_node in yaml_mapping_values(root, "jobs"):
            if not isinstance(jobs_node, yaml.MappingNode):
                continue
            for _, job_node in jobs_node.value:
                step_collections.extend(yaml_mapping_values(job_node, "steps"))
    elif COMPOSITE_ACTIONS in path.parents:
        for runs_node in yaml_mapping_values(root, "runs"):
            step_collections.extend(yaml_mapping_values(runs_node, "steps"))

    for steps_node in step_collections:
        if not isinstance(steps_node, yaml.SequenceNode):
            location = (
                f"{path.relative_to(ROOT)}:{steps_node.start_mark.line + 1}"
            )
            failures.append(f"{location}: steps must be a sequence")
            continue
        for step in steps_node.value:
            if not isinstance(step, yaml.MappingNode):
                location = f"{path.relative_to(ROOT)}:{step.start_mark.line + 1}"
                failures.append(
                    f"{location}: action step aliases must resolve to mappings"
                )
                continue
            step_failures, step_discovered = scan_yaml_action_step(path, step)
            failures.extend(step_failures)
            discovered += step_discovered
    return failures, discovered


def yaml_parser_failures():
    cases = (
        """
jobs:
  test:
    steps:
      -   name: Checkout
          uses: actions/checkout@v4
""",
        """
jobs:
  test:
    steps:
      - uses:
          actions/checkout@v4
""",
        """
jobs:
  test:
    steps: [ { uses: actions/checkout@v4 } ]
""",
    )
    failures = []
    fixture_path = WORKFLOWS / "runtime-policy-fixture.yml"
    for source in cases:
        findings, discovered = scan_parsed_yaml(fixture_path, source)
        if discovered != 1 or not any(
            "unsupported actions/checkout@v4" in finding
            for finding in findings
        ):
            failures.append("semantic YAML parser missed action fixture")

    alias_source = """
node-inputs: &node-inputs
  package-manager-cache: false
jobs:
  test:
    steps:
      - uses: actions/setup-node@v7
        with: *node-inputs
"""
    findings, discovered = scan_parsed_yaml(fixture_path, alias_source)
    if findings or discovered != 1:
        failures.append("semantic YAML parser missed input alias fixture")
    unrelated_steps_source = """
on:
  workflow_call:
    inputs:
      steps:
        type: string
jobs:
  test:
    env:
      steps: hello
    steps:
      - uses: actions/checkout@v7
"""
    findings, discovered = scan_parsed_yaml(
        fixture_path, unrelated_steps_source
    )
    if findings or discovered != 1:
        failures.append("semantic YAML parser promoted unrelated steps fixture")
    return failures


def unsupported_steps_collections(lines):
    scalar_content = block_scalar_content_indices(lines)
    unsupported = []
    for index, line in enumerate(lines):
        if index in scalar_content:
            continue
        entry = block_mapping_entry(line)
        if not entry or entry[1] or entry[2] != "steps":
            continue
        value = SCALAR_PREFIX_PATTERN.sub("", entry[3], count=1).strip()
        if value and not value.startswith("#"):
            unsupported.append(index)
    return unsupported


def step_cache_status(lines, start, indentation, list_marker):
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
        with_entry = block_mapping_entry(lines[index])
        if not with_entry or with_entry[2] != "with":
            continue
        with_indentation = len(with_entry[0]) + (2 if with_entry[1] else 0)
        if with_indentation != step_key_indentation:
            continue
        with_value = strip_yaml_comment(with_entry[3])
        with_value = SCALAR_PREFIX_PATTERN.sub("", with_value, count=1).strip()
        if YAML_ALIAS_PATTERN.fullmatch(with_value):
            return "alias"
        if with_value.startswith("{"):
            return flow_mapping_cache_status(with_value)
        if with_value and not with_value.startswith("#"):
            continue

        input_indentation = None
        for input_index in range(index + 1, step_end):
            line = lines[input_index]
            key_match = re.match(r"^(\s*)\S", line)
            if key_match and len(key_match.group(1)) <= step_key_indentation:
                break
            input_entry = block_mapping_entry(line)
            if not input_entry or input_entry[1]:
                continue
            current_indentation = len(input_entry[0])
            if input_indentation is None:
                input_indentation = current_indentation
            if current_indentation != input_indentation:
                continue
            if input_entry[2] == "package-manager-cache":
                input_value = input_entry[3]
                if is_block_scalar_value(input_value):
                    input_value = block_scalar_value(
                        lines, input_index, current_indentation
                    )
                if input_value is not None and scalar_is_false(input_value):
                    return "disabled"
    return "missing"


def flow_step_cache_status(line):
    flow_step = flow_step_mapping(line)
    if not flow_step:
        return "missing"
    with_value = flow_mapping_value(flow_step[1], "with")
    if with_value and YAML_ALIAS_PATTERN.fullmatch(with_value):
        return "alias"
    return flow_mapping_cache_status(with_value) if with_value else "missing"


def flow_mapping_cache_status(value):
    entries = parse_flow_mapping(value)
    if entries is None:
        return "missing"
    cache_value = flow_mapping_value(entries, "package-manager-cache")
    return "disabled" if cache_value and scalar_is_false(cache_value) else "missing"


def action_cache_status(lines, start, parsed):
    indentation, list_marker, _, _, flow_mapping_line = parsed
    if flow_mapping_line:
        return flow_step_cache_status(flow_mapping_line)
    return step_cache_status(lines, start, len(indentation), list_marker)


def action_has_cache_disabled(lines, start, parsed):
    return action_cache_status(lines, start, parsed) == "disabled"


def main():
    failures = (
        parser_failures()
        + cache_parser_failures()
        + coverage_failures()
        + dependency_callsite_failures()
        + yaml_parser_failures()
    )
    discovered = 0

    for path in workflow_files():
        if WORKFLOWS in path.parents or COMPOSITE_ACTIONS in path.parents:
            yaml_failures, yaml_discovered = scan_parsed_yaml(path)
            failures.extend(yaml_failures)
            discovered += yaml_discovered
            continue
        lines = path.read_text().splitlines()
        normalized_lines = [normalize_workflow_line(line) for line in lines]
        policy_lines = (
            normalized_lines if PLUGIN_TEMPLATES in path.parents else lines
        )
        for index in unsupported_steps_collections(policy_lines):
            location = f"{path.relative_to(ROOT)}:{index + 1}"
            failures.append(
                f"{location}: steps must use a block-style sequence"
            )
        scalar_content = block_scalar_content_indices(lines)
        normalized_scalar_content = (
            block_scalar_content_indices(normalized_lines)
            if PLUGIN_TEMPLATES in path.parents
            else set()
        )
        joined_flow_lines, flow_continuations = flow_step_lines(lines)
        if PLUGIN_TEMPLATES in path.parents:
            normalized_flow_lines, normalized_flow_continuations = flow_step_lines(
                normalized_lines
            )
        else:
            normalized_flow_lines, normalized_flow_continuations = {}, set()
        for index, line in enumerate(lines):
            if (
                index in scalar_content
                or index in normalized_scalar_content
                or index in flow_continuations
                or index in normalized_flow_continuations
            ):
                continue
            candidate_line = joined_flow_lines.get(index, line)
            parsed = (
                parse_action(candidate_line)
                or parse_block_scalar_action(lines, index)
                or parse_explicit_action(lines, index)
            )
            scanned_lines = lines
            if not parsed and PLUGIN_TEMPLATES in path.parents:
                candidate_line = normalized_flow_lines.get(
                    index, normalized_lines[index]
                )
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
                if action_cache_status(scanned_lines, index, parsed) == "alias":
                    failures.append(
                        f"{location}: setup-node input aliases are not supported"
                    )
                else:
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
