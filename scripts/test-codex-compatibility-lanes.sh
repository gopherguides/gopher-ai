#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/integration-tests.yml"
LIFECYCLE_TEST="$ROOT_DIR/scripts/test-codex-plugin-lifecycle.sh"

ruby -ryaml - "$WORKFLOW" <<'RUBY'
workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
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

expected_probes = [
  "./scripts/test-codex-plugin-lifecycle.sh",
  "python3 ./scripts/test-codex-default-mode-input.py",
  "python3 ./scripts/test-codex-skill-names.py",
  "python3 ./scripts/test-codex-skill-arguments.py",
]
runs = steps.map { |step| step["run"] }.compact
missing_probes = expected_probes - runs
abort "Codex matrix job omits probes: #{missing_probes.join(', ')}" unless missing_probes.empty?
RUBY

rg -q '^EXPECTED_CODEX_VERSION="\$\{CODEX_LIFECYCLE_EXPECTED_VERSION:-\}"$' "$LIFECYCLE_TEST" \
    || { printf 'lifecycle test still defaults to a hard-coded Codex version\n' >&2; exit 1; }
rg -Fq "ACTUAL_CODEX_VERSION=\"\$(awk '\$1 == \"codex-cli\" { print \$2; exit }' <<< \"\$CODEX_VERSION_OUTPUT\")\"" "$LIFECYCLE_TEST" \
    || { printf 'lifecycle test does not tolerate warnings before the Codex version\n' >&2; exit 1; }
rg -q "^printf 'Codex CLI version: %s\\\\n' \"\\\$ACTUAL_CODEX_VERSION\"$" "$LIFECYCLE_TEST" \
    || { printf 'lifecycle test does not print the resolved Codex version\n' >&2; exit 1; }

printf 'Codex compatibility lane tests passed.\n'
