#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/integration-tests.yml"
LIFECYCLE_TEST="$ROOT_DIR/scripts/test-codex-plugin-lifecycle.sh"
TAILWIND_MCP_PROBE="$ROOT_DIR/scripts/test-tailwind-mcp-server.mjs"

ruby -ryaml - "$WORKFLOW" "$LIFECYCLE_TEST" "$TAILWIND_MCP_PROBE" <<'RUBY'
workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
lifecycle_source = File.read(ARGV.fetch(1))
tailwind_mcp_probe_source = File.read(ARGV.fetch(2))
job = workflow.dig("jobs", "test-codex-plugin-lifecycle")
abort "missing Codex lifecycle job" unless job

abort "Codex compatibility matrix must disable fail-fast" unless job.dig("strategy", "fail-fast") == false

expected_lanes = [
  {
    "lane" => "minimum",
    "codex-version" => "0.146.0",
    "expected-version" => "0.146.0",
  },
  {
    "lane" => "current",
    "codex-version" => "latest",
    "expected-version" => "",
  },
]
actual_lanes = job.dig("strategy", "matrix", "include")
abort "Codex compatibility matrix does not define minimum and current lanes" unless actual_lanes == expected_lanes

name = job.fetch("name", "")
abort "Codex compatibility job name does not identify its lane" unless name.include?("${{ matrix.lane }}")

steps = job.fetch("steps", [])
install = steps.find { |step| step["name"] == "Install Codex CLI" }
expected_install = 'npm install --global "@openai/codex@${{ matrix.codex-version }}"'
abort "Codex install does not use the matrix version" unless install&.fetch("run", "") == expected_install

lifecycle = steps.find { |step| step["name"] == "Test real Codex plugin lifecycle" }
expected_version = "${{ matrix.expected-version }}"
unless lifecycle&.dig("env", "CODEX_LIFECYCLE_EXPECTED_VERSION") == expected_version
  abort "Codex lifecycle expectation does not use the matrix value"
end

tailwind_install = steps.find { |step| step["name"] == "Install pinned Tailwind MCP server" }
expected_tailwind_env = {
  "TAILWIND_MCP_INSTALL_ROOT" => "${{ runner.temp }}/gopher-ai-tailwind-mcp-install",
  "npm_config_cache" => "${{ runner.temp }}/gopher-ai-tailwind-mcp-npm-cache",
}
expected_tailwind_install = 'npm install --prefix "$TAILWIND_MCP_INSTALL_ROOT" --no-save --package-lock=false "tailwindcss-mcp-server@0.1.1"'
abort "Tailwind MCP install must have its own three-minute timeout" unless tailwind_install&.fetch("timeout-minutes", nil) == 3
abort "Tailwind MCP install does not use the isolated runner paths" unless tailwind_install&.fetch("env", nil) == expected_tailwind_env
abort "Tailwind MCP install does not use the pinned package" unless tailwind_install&.fetch("run", "") == expected_tailwind_install

tailwind_probe = steps.find { |step| step["name"] == "Probe declared Tailwind MCP tools" }
abort "Tailwind MCP probe must have its own two-minute timeout" unless tailwind_probe&.fetch("timeout-minutes", nil) == 2
abort "Tailwind MCP probe does not reuse the isolated install" unless tailwind_probe&.fetch("env", nil) == expected_tailwind_env
abort "Tailwind MCP probe command changed unexpectedly" unless tailwind_probe&.fetch("run", "") == "node ./scripts/test-tailwind-mcp-server.mjs"
abort "Tailwind MCP install must run before the protocol probe" unless steps.index(tailwind_install) < steps.index(tailwind_probe)
abort "Tailwind MCP probe lacks a named response timeout" unless tailwind_mcp_probe_source.include?("const responseTimeoutMs = 30000;")
abort "Tailwind MCP requests do not use the response timeout" unless tailwind_mcp_probe_source.include?("}, responseTimeoutMs);")
abort "Tailwind MCP probe does not resolve the preinstalled server binary" unless tailwind_mcp_probe_source.include?("async function resolveServerLaunch(packageSpec)")

expected_probes = [
  "./scripts/test-codex-plugin-lifecycle.sh",
  "python3 ./scripts/test-codex-default-mode-input.py",
  "python3 ./scripts/test-codex-skill-names.py",
  "python3 ./scripts/test-codex-skill-arguments.py",
]
runs = steps.map { |step| step["run"] }.compact
missing_probes = expected_probes - runs
abort "Codex matrix job omits probes: #{missing_probes.join(', ')}" unless missing_probes.empty?

expected_source = [
  'EXPECTED_CODEX_VERSION="${CODEX_LIFECYCLE_EXPECTED_VERSION:-}"',
  'ACTUAL_CODEX_VERSION="$(awk \'$1 == "codex-cli" { print $2; exit }\' <<< "$CODEX_VERSION_OUTPUT")"',
  'printf \'Codex CLI version: %s\\n\' "$ACTUAL_CODEX_VERSION"',
]
missing_source = expected_source.reject { |line| lifecycle_source.lines(chomp: true).include?(line) }
unless missing_source.empty?
  abort "Codex lifecycle version contract is incomplete: #{missing_source.join(', ')}"
end
RUBY

MISSING_INSTALL_ROOT="${TMPDIR:-/tmp}/gopher-ai-tailwind-mcp-missing-$$"
if missing_install_output=$(
    TAILWIND_MCP_INSTALL_ROOT="$MISSING_INSTALL_ROOT" \
        node "$TAILWIND_MCP_PROBE" 2>&1
); then
    printf 'Tailwind MCP probe unexpectedly accepted a missing preinstall.\n' >&2
    exit 1
fi
if [[ "$missing_install_output" != *"FAIL: Tailwind MCP installation is not ready:"* ]]; then
    printf 'Tailwind MCP probe did not distinguish installation readiness failure.\n%s\n' \
        "$missing_install_output" >&2
    exit 1
fi
if [[ "$missing_install_output" == *"timed out waiting for server/discover"* ]]; then
    printf 'Tailwind MCP installation failure leaked into the response timeout.\n' >&2
    exit 1
fi

printf 'Codex compatibility lane tests passed.\n'
