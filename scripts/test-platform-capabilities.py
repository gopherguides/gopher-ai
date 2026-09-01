#!/usr/bin/env python3

import json
import re
from collections import Counter
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
MATRIX_PATH = ROOT_DIR / "docs/platform-capabilities.json"
DOCUMENTATION_PATH = ROOT_DIR / "docs/platform-capabilities.md"
README_PATH = ROOT_DIR / "README.md"
PLATFORMS = {"claude_code", "codex"}
CODEX_DISPOSITIONS = {"skill", "mcp_tool", "unsupported"}
COUNT_PATTERN = re.compile(
    r"Shipped surface: (\d+) Claude Code commands across (\d+) plugins; "
    r"(\d+) Codex skills across (\d+) plugins; "
    r"(\d+) optional Codex MCP tools\."
)
ISSUE_PATTERN = re.compile(
    r"https://github\.com/gopherguides/gopher-ai/issues/[1-9][0-9]*"
)


def fail(message):
    raise AssertionError(message)


def load_json(path, label):
    if not path.is_file():
        fail(f"missing {label}: {path.relative_to(ROOT_DIR)}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        fail(f"invalid JSON in {path.relative_to(ROOT_DIR)}: {error}")


def relative_source_paths(pattern):
    return {
        path.relative_to(ROOT_DIR).as_posix()
        for path in ROOT_DIR.glob(pattern)
        if path.is_file()
    }


def frontmatter_name(path):
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        fail(f"skill is missing frontmatter: {path.relative_to(ROOT_DIR)}")
    try:
        end = lines.index("---", 1)
    except ValueError:
        fail(f"skill has unterminated frontmatter: {path.relative_to(ROOT_DIR)}")
    names = []
    for line in lines[1:end]:
        match = re.fullmatch(r"name:\s*['\"]?([^'\"\s]+)['\"]?\s*", line)
        if match:
            names.append(match.group(1))
    if len(names) != 1:
        fail(
            f"skill must have exactly one frontmatter name: "
            f"{path.relative_to(ROOT_DIR)}"
        )
    return names[0]


def validate_documentation_reference(reference):
    path_text, separator, fragment = reference.partition("#")
    relative_path = Path(path_text)
    if relative_path.is_absolute() or ".." in relative_path.parts:
        fail(f"documentation reference must stay inside the repository: {reference}")
    path = ROOT_DIR / relative_path
    if not path.is_file():
        fail(f"documentation reference does not exist: {reference}")
    if separator:
        headings = re.findall(
            r"^#{1,6}\s+(.+?)\s*$", path.read_text(encoding="utf-8"), re.MULTILINE
        )
        anchors = {
            re.sub(r"[^a-z0-9 -]", "", heading.lower()).replace(" ", "-")
            for heading in headings
        }
        if fragment not in anchors:
            fail(f"documentation anchor does not exist: {reference}")


def validate_counts(path, expected):
    if not path.is_file():
        fail(f"missing documentation: {path.relative_to(ROOT_DIR)}")
    match = COUNT_PATTERN.search(path.read_text(encoding="utf-8"))
    if not match:
        fail(
            f"{path.relative_to(ROOT_DIR)} is missing the canonical shipped-surface "
            "count statement"
        )
    actual = tuple(int(value) for value in match.groups())
    if actual != expected:
        fail(
            f"stale shipped-surface counts in {path.relative_to(ROOT_DIR)}: "
            f"expected {expected}, got {actual}"
        )


def documented_section_names(cell, section, pattern):
    match = re.search(rf"(?:^|\. ){section}s?: (.*?)(?:\.|$)", cell)
    if not match:
        return []
    return re.findall(pattern, match.group(1))


def validate_documentation(matrix, expected_counts):
    validate_counts(DOCUMENTATION_PATH, expected_counts)
    text = DOCUMENTATION_PATH.read_text(encoding="utf-8")
    row_matches = re.findall(
        r"^\| `([^`]+)` \| (.+?) \| (.+?) \|$", text, re.MULTILINE
    )
    row_counts = Counter(plugin for plugin, _, _ in row_matches)
    plugin_names = {plugin["name"] for plugin in matrix["plugins"]}
    if row_counts != Counter({plugin: 1 for plugin in plugin_names}):
        fail(
            "documentation plugin rows differ from the matrix: "
            f"expected={sorted(plugin_names)}, got={dict(sorted(row_counts.items()))}"
        )
    rows = {plugin: (claude, codex) for plugin, claude, codex in row_matches}

    resolved_issues = {"go-web": {"323"}, "gopher-guides": {"337"}}
    for plugin in matrix["plugins"]:
        plugin_name = plugin["name"]
        capabilities = [
            capability
            for capability in matrix["capabilities"]
            if capability["plugin"] == plugin_name
        ]
        claude_cell, codex_cell = rows[plugin_name]
        expected_claude_commands = Counter(
            Path(source["path"]).stem
            for capability in capabilities
            for source in capability["sources"]
            if source["kind"] == "command"
        )
        documented_claude_commands = Counter(
            documented_section_names(
                claude_cell, "Command", r"`([a-z][a-z0-9-]*)`"
            )
        )
        if documented_claude_commands != expected_claude_commands:
            fail(
                f"documentation Claude commands differ for {plugin_name}: "
                f"expected={dict(sorted(expected_claude_commands.items()))}, "
                f"got={dict(sorted(documented_claude_commands.items()))}"
            )

        expected_claude_skills = Counter(
            Path(source["path"]).parent.name
            for capability in capabilities
            for source in capability["sources"]
            if source["kind"] == "skill"
        )
        documented_claude_skills = Counter(
            documented_section_names(
                claude_cell, "Skill", r"`([a-z][a-z0-9-]*)`"
            )
        )
        if documented_claude_skills != expected_claude_skills:
            fail(
                f"documentation Claude skills differ for {plugin_name}: "
                f"expected={dict(sorted(expected_claude_skills.items()))}, "
                f"got={dict(sorted(documented_claude_skills.items()))}"
            )

        expected_codex_skills = Counter(
            capability["platforms"]["codex"]["name"]
            for capability in capabilities
            if capability["platforms"]["codex"]["disposition"] == "skill"
        )
        documented_codex_skills = Counter(
            documented_section_names(
                codex_cell,
                "Skill",
                r"\$([a-z][a-z0-9-]*:[a-z][a-z0-9-]*)",
            )
        )
        if documented_codex_skills != expected_codex_skills:
            fail(
                f"documentation Codex skills differ for {plugin_name}: "
                f"expected={dict(sorted(expected_codex_skills.items()))}, "
                f"got={dict(sorted(documented_codex_skills.items()))}"
            )

        unsupported = [
            capability
            for capability in capabilities
            if capability["platforms"]["codex"]["disposition"] == "unsupported"
        ]
        if unsupported and "unsupported" not in codex_cell.lower():
            fail(f"documentation omits unsupported status for {plugin_name}")
        expected_issue_names = {
            capability["platforms"]["codex"]["issue"].rsplit("/", 1)[-1]
            for capability in unsupported
            if "issue" in capability["platforms"]["codex"]
        } | resolved_issues.get(plugin_name, set())
        expected_issues = Counter({issue: 1 for issue in expected_issue_names})
        documented_issues = Counter(
            re.findall(
                r"https://github\.com/gopherguides/gopher-ai/issues/([1-9][0-9]*)",
                codex_cell,
            )
        )
        if documented_issues != expected_issues:
            fail(
                f"documentation issue links differ for {plugin_name}: "
                f"expected={dict(sorted(expected_issues.items()))}, "
                f"got={dict(sorted(documented_issues.items()))}"
            )

    mcp_capabilities = [
        capability
        for capability in matrix["capabilities"]
        if capability["platforms"]["codex"]["disposition"] == "mcp_tool"
    ]
    expected_mcp_names = Counter(
        name.rsplit("__", 1)[-1]
        for capability in mcp_capabilities
        for name in capability["platforms"]["codex"]["names"]
    )
    mcp_text = text.partition("The optional Tailwind MCP server exposes")[2]
    mcp_text = mcp_text.partition("These supplementary tools")[0]
    documented_mcp_names = Counter(
        re.findall(r"`([a-z][a-z0-9_]*)`", mcp_text)
    )
    if documented_mcp_names != expected_mcp_names:
        fail(
            "documentation MCP tools differ from the matrix: "
            f"expected={dict(sorted(expected_mcp_names.items()))}, "
            f"got={dict(sorted(documented_mcp_names.items()))}"
        )


def validate_plugins(matrix):
    records = matrix.get("plugins")
    if not isinstance(records, list) or not records:
        fail("matrix plugins must be a non-empty list")
    names = [record.get("name") for record in records]
    duplicates = sorted(name for name, count in Counter(names).items() if count > 1)
    if duplicates:
        fail(f"duplicate matrix plugins: {duplicates}")

    claude_plugins = {
        path.parent.parent.name
        for path in ROOT_DIR.glob("plugins/*/.claude-plugin/plugin.json")
    }
    codex_plugins = {
        path.parent.parent.name
        for path in ROOT_DIR.glob("plugins/*/.codex-plugin/plugin.json")
    }
    marketplace = load_json(
        ROOT_DIR / ".agents/plugins/marketplace.json", "Codex marketplace"
    )
    marketplace_entries = marketplace.get("plugins", [])
    marketplace_name_list = [entry.get("name") for entry in marketplace_entries]
    marketplace_duplicates = sorted(
        name
        for name, count in Counter(marketplace_name_list).items()
        if count > 1
    )
    if marketplace_duplicates:
        fail(f"duplicate Codex marketplace plugins: {marketplace_duplicates}")
    marketplace_names = set(marketplace_name_list)
    if marketplace_names != codex_plugins:
        fail(
            "Codex marketplace/manifests disagree: "
            f"marketplace={sorted(marketplace_names)}, manifests={sorted(codex_plugins)}"
        )
    for entry in marketplace_entries:
        expected_path = f"./plugins/{entry['name']}"
        if entry.get("source") != {"source": "local", "path": expected_path}:
            fail(f"invalid marketplace source for {entry['name']}: {entry.get('source')}")
        manifest = load_json(
            ROOT_DIR / f"plugins/{entry['name']}/.codex-plugin/plugin.json",
            f"{entry['name']} Codex manifest",
        )
        if manifest.get("name") != entry["name"] or manifest.get("skills") != "./skills/":
            fail(f"invalid Codex manifest identity or skill path for {entry['name']}")

    if set(names) != claude_plugins:
        fail(
            "matrix plugin inventory differs from Claude manifests: "
            f"matrix={sorted(names)}, manifests={sorted(claude_plugins)}"
        )

    supported_codex = set()
    plugin_records = {}
    for record in records:
        name = record.get("name")
        platforms = record.get("platforms")
        if not isinstance(platforms, dict) or set(platforms) != PLATFORMS:
            fail(f"plugin {name} must declare exactly {sorted(PLATFORMS)}")
        if platforms["claude_code"] != {"status": "supported"}:
            fail(f"plugin {name} must match its shipped Claude manifest")
        codex = platforms["codex"]
        if codex.get("status") == "supported":
            if set(codex) != {"status"}:
                fail(f"supported Codex plugin {name} has unexpected status fields")
            supported_codex.add(name)
        elif codex == {
            "status": "unsupported",
            "reason": "intentionally_claude_only",
        }:
            pass
        else:
            fail(f"invalid Codex plugin status for {name}: {codex}")
        plugin_records[name] = record

    if supported_codex != codex_plugins:
        fail(
            "matrix Codex support differs from marketplace/manifests: "
            f"matrix={sorted(supported_codex)}, shipped={sorted(codex_plugins)}"
        )
    return plugin_records, supported_codex


def validate_capabilities(matrix, plugin_records, supported_codex):
    capabilities = matrix.get("capabilities")
    if not isinstance(capabilities, list) or not capabilities:
        fail("matrix capabilities must be a non-empty list")
    identifiers = [capability.get("id") for capability in capabilities]
    duplicates = sorted(
        identifier
        for identifier, count in Counter(identifiers).items()
        if count > 1
    )
    if duplicates:
        fail(f"duplicate capability ids: {duplicates}")

    discovered_commands = relative_source_paths("plugins/*/commands/*.md")
    discovered_skills = relative_source_paths("plugins/*/skills/*/SKILL.md")
    covered_commands = []
    covered_skills = []
    declared_skill_names = []
    mcp_tool_names = []

    for capability in capabilities:
        identifier = capability.get("id")
        plugin = capability.get("plugin")
        if plugin not in plugin_records:
            fail(f"capability {identifier} references unknown plugin {plugin}")
        if not isinstance(identifier, str) or not identifier.startswith(f"{plugin}."):
            fail(f"capability id must start with {plugin}.: {identifier}")
        if not isinstance(capability.get("summary"), str) or not capability["summary"]:
            fail(f"capability {identifier} is missing a summary")

        sources = capability.get("sources")
        if not isinstance(sources, list) or not sources:
            fail(f"capability {identifier} must declare source files")
        source_kinds = []
        skill_sources = []
        for source in sources:
            if not isinstance(source, dict) or set(source) != {"kind", "path"}:
                fail(f"capability {identifier} has an invalid source mapping")
            kind = source["kind"]
            source_text = source["path"]
            source_path = Path(source_text)
            path = ROOT_DIR / source_path
            if source_path.is_absolute() or ".." in source_path.parts:
                fail(f"capability {identifier} has a non-relative source: {source_text}")
            if not path.is_file():
                fail(f"capability {identifier} source does not exist: {source_text}")
            parts = Path(source_text).parts
            if len(parts) < 2 or parts[0] != "plugins" or parts[1] != plugin:
                fail(f"capability {identifier} source belongs to another plugin: {source_text}")
            if kind == "command":
                covered_commands.append(source_text)
                if source_text not in discovered_commands:
                    fail(f"capability {identifier} has an invalid command source: {source_text}")
            elif kind == "skill":
                covered_skills.append(source_text)
                skill_sources.append(source_text)
                if source_text not in discovered_skills:
                    fail(f"capability {identifier} has an invalid skill source: {source_text}")
            elif kind == "mcp_manifest":
                if Path(source_text).name != ".mcp.json":
                    fail(f"capability {identifier} has an invalid MCP source: {source_text}")
            else:
                fail(f"capability {identifier} has an invalid source kind: {kind}")
            source_kinds.append(kind)

        platforms = capability.get("platforms")
        if not isinstance(platforms, dict) or set(platforms) != PLATFORMS:
            fail(f"capability {identifier} must map exactly {sorted(PLATFORMS)}")
        claude = platforms["claude_code"]
        if "command" in source_kinds:
            expected_claude_disposition = "command"
        elif "skill" in source_kinds:
            expected_claude_disposition = "skill"
        else:
            expected_claude_disposition = "mcp_tool"
        if claude.get("disposition") != expected_claude_disposition:
            fail(
                f"capability {identifier} must use Claude disposition "
                f"{expected_claude_disposition}"
            )
        claude_names = claude.get("names")
        if not isinstance(claude_names, list) or not claude_names:
            fail(f"capability {identifier} must declare Claude names")
        if expected_claude_disposition == "command":
            expected_command_names = sorted(
                f"{plugin}:{Path(source['path']).stem}"
                for source in sources
                if source["kind"] == "command"
            )
            if sorted(claude_names) != expected_command_names:
                fail(
                    f"capability {identifier} Claude command names differ from sources: "
                    f"expected {expected_command_names}, got {sorted(claude_names)}"
                )
            expected_skill_names = sorted(
                f"{plugin}:{frontmatter_name(ROOT_DIR / source_path)}"
                for source_path in skill_sources
            )
            claude_skill_names = claude.get("skill_names")
            if expected_skill_names:
                if not isinstance(claude_skill_names, list) or not claude_skill_names:
                    fail(
                        f"capability {identifier} must declare mixed Claude skill names"
                    )
                if sorted(claude_skill_names) != expected_skill_names:
                    fail(
                        f"capability {identifier} Claude skill names differ from sources: "
                        f"expected {expected_skill_names}, "
                        f"got {sorted(claude_skill_names)}"
                    )
            elif "skill_names" in claude:
                fail(
                    f"command-only capability {identifier} declares Claude skill names"
                )

        codex = platforms["codex"]
        disposition = codex.get("disposition")
        if disposition not in CODEX_DISPOSITIONS:
            fail(f"capability {identifier} has invalid Codex disposition: {disposition}")
        if skill_sources and disposition != "skill":
            fail(f"Codex skill source in {identifier} is not classified as a skill")
        if disposition == "skill":
            if plugin not in supported_codex:
                fail(f"unsupported Codex plugin {plugin} declares a skill")
            if set(codex) != {"disposition", "name"}:
                fail(f"capability {identifier} has invalid Codex skill fields")
            if len(skill_sources) != 1:
                fail(f"Codex skill capability {identifier} must own one skill source")
            source_path = ROOT_DIR / skill_sources[0]
            expected_name = f"{plugin}:{frontmatter_name(source_path)}"
            if codex["name"] != expected_name:
                fail(
                    f"capability {identifier} Codex name differs from skill source: "
                    f"expected {expected_name}, got {codex['name']}"
                )
            declared_skill_names.append(codex["name"])
            if claude.get("disposition") == "skill" and claude_names != [expected_name]:
                fail(
                    f"capability {identifier} Claude skill name differs from source: "
                    f"expected {[expected_name]}, got {claude_names}"
                )
        elif disposition == "mcp_tool":
            if plugin not in supported_codex:
                fail(f"unsupported Codex plugin {plugin} declares MCP tools")
            if set(codex) != {"disposition", "names"}:
                fail(f"capability {identifier} has invalid Codex MCP fields")
            names = codex["names"]
            if not isinstance(names, list) or not names:
                fail(f"capability {identifier} must declare MCP tool names")
            if source_kinds != ["mcp_manifest"]:
                fail(
                    f"capability {identifier} MCP tools must own only one MCP manifest"
                )
            invalid_names = sorted(
                name
                for name in names
                if not re.fullmatch(r"mcp__[a-z0-9_-]+__[a-z][a-z0-9_]*", name)
            )
            if invalid_names:
                fail(f"capability {identifier} has invalid MCP tool names: {invalid_names}")
            manifest = load_json(
                ROOT_DIR / f"plugins/{plugin}/.codex-plugin/plugin.json",
                f"{plugin} Codex manifest",
            )
            if "mcpServers" not in manifest:
                fail(f"capability {identifier} plugin manifest does not expose MCP")
            if claude_names != names:
                fail(
                    f"capability {identifier} Claude and Codex MCP names differ: "
                    f"Claude={claude_names}, Codex={names}"
                )
            mcp_tool_names.extend(names)
        else:
            expected_fields = {"disposition", "documentation"}
            if plugin_records[plugin]["platforms"]["codex"].get("reason") != (
                "intentionally_claude_only"
            ):
                expected_fields.add("issue")
            if set(codex) != expected_fields:
                fail(f"capability {identifier} has invalid unsupported fields")
            validate_documentation_reference(codex["documentation"])
            if "issue" in codex and not ISSUE_PATTERN.fullmatch(codex["issue"]):
                fail(f"capability {identifier} has invalid issue reference")
            if skill_sources:
                fail(f"unsupported capability {identifier} owns a Codex skill source")

    for label, discovered, covered in (
        ("command", discovered_commands, covered_commands),
        ("skill", discovered_skills, covered_skills),
    ):
        counter = Counter(covered)
        duplicate_sources = sorted(path for path, count in counter.items() if count > 1)
        if duplicate_sources:
            fail(f"duplicate {label} source coverage: {duplicate_sources}")
        missing = sorted(discovered - set(covered))
        extra = sorted(set(covered) - discovered)
        if missing or extra:
            fail(f"incomplete {label} source coverage: missing={missing}, extra={extra}")

    duplicate_skill_names = sorted(
        name for name, count in Counter(declared_skill_names).items() if count > 1
    )
    if duplicate_skill_names:
        fail(f"duplicate declared Codex skill names: {duplicate_skill_names}")
    duplicate_mcp_names = sorted(
        name for name, count in Counter(mcp_tool_names).items() if count > 1
    )
    if duplicate_mcp_names:
        fail(f"duplicate declared Codex MCP tool names: {duplicate_mcp_names}")
    return (
        len(discovered_commands),
        len(plugin_records),
        len(declared_skill_names),
        len(supported_codex),
        len(mcp_tool_names),
    )


def main():
    matrix = load_json(MATRIX_PATH, "canonical platform capability matrix")
    if matrix.get("schema_version") != 1:
        fail(f"unsupported matrix schema_version: {matrix.get('schema_version')}")
    if set(matrix) != {"schema_version", "plugins", "capabilities"}:
        fail(f"unexpected top-level matrix fields: {sorted(matrix)}")

    plugin_records, supported_codex = validate_plugins(matrix)
    expected_counts = validate_capabilities(matrix, plugin_records, supported_codex)
    validate_counts(README_PATH, expected_counts)
    validate_documentation(matrix, expected_counts)
    readme = README_PATH.read_text(encoding="utf-8")
    if "[platform capability matrix](docs/platform-capabilities.md)" not in readme:
        fail("README.md does not link the platform capability matrix")

    print(
        "Platform capability matrix passed: "
        f"{expected_counts[0]} commands, {expected_counts[2]} Codex skills, "
        f"{expected_counts[4]} Codex MCP tools"
    )


if __name__ == "__main__":
    main()
