#!/usr/bin/env node

import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const claudeManifestPath = resolve(root, "plugins/tailwind/.claude-plugin/plugin.json");
const mcpManifestPath = resolve(root, "plugins/tailwind/.mcp.json");
const protocolVersion = "2026-07-28";
const legacyProtocolVersion = "2024-11-05";
const requiredTools = [
  "search_tailwind_docs",
  "get_tailwind_utilities",
  "get_tailwind_colors",
  "convert_css_to_tailwind",
  "generate_component_template",
  "install_tailwind",
  "get_tailwind_config_guide",
];

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

const [claudeManifest, mcpManifest] = await Promise.all([
  readJson(claudeManifestPath),
  readJson(mcpManifestPath),
]);
const claudeConfig = claudeManifest.mcpServers?.tailwindcss;
const serverConfig = mcpManifest.tailwindcss;

assert(claudeConfig, "Claude manifest is missing the tailwindcss MCP server");
assert(serverConfig, "MCP manifest is missing the tailwindcss server");
assert(
  JSON.stringify(claudeConfig) === JSON.stringify(serverConfig),
  "Claude and shared MCP server configurations differ",
);
assert(serverConfig.command === "npx", "tailwindcss MCP server must run with npx");
assert(serverConfig.args?.[0] === "-y", "tailwindcss MCP server must pass npx -y");

const packageSpec = serverConfig.args?.[1];
assert(
  /^tailwindcss-mcp-server@\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(packageSpec ?? ""),
  "tailwindcss-mcp-server must use an explicit semantic version",
);

const tempRoot =
  process.env.TMPDIR ?? process.env.TMP ?? process.env.TEMP ?? "/tmp";
const npmCache =
  process.env.npm_config_cache ??
  resolve(tempRoot, "gopher-ai-tailwind-mcp-npm-cache");
const child = spawn(serverConfig.command, serverConfig.args, {
  cwd: root,
  env: {
    ...process.env,
    npm_config_cache: npmCache,
  },
  stdio: ["pipe", "pipe", "pipe"],
});

child.stdout.setEncoding("utf8");
child.stderr.setEncoding("utf8");

let stdoutBuffer = "";
let stderr = "";
const nonProtocolLines = [];
const pending = new Map();

function rejectPending(error) {
  for (const { reject, timer } of pending.values()) {
    clearTimeout(timer);
    reject(error);
  }
  pending.clear();
}

function handleLine(line) {
  if (!line.trim()) {
    return;
  }

  let message;
  try {
    message = JSON.parse(line);
  } catch {
    nonProtocolLines.push(line);
    return;
  }

  const request = pending.get(String(message.id));
  if (!request) {
    return;
  }

  clearTimeout(request.timer);
  pending.delete(String(message.id));
  request.resolve(message);
}

child.stdout.on("data", (chunk) => {
  stdoutBuffer += chunk;
  const lines = stdoutBuffer.split("\n");
  stdoutBuffer = lines.pop() ?? "";
  for (const line of lines) {
    handleLine(line);
  }
});
child.stderr.on("data", (chunk) => {
  stderr += chunk;
});
child.on("error", rejectPending);
child.on("exit", (code, signal) => {
  if (pending.size > 0) {
    rejectPending(
      new Error(
        `tailwindcss MCP server exited before responding (code=${code}, signal=${signal})`,
      ),
    );
  }
});

function send(message) {
  child.stdin.write(`${JSON.stringify(message)}\n`);
}

function request(id, method, params) {
  return new Promise((resolveRequest, rejectRequest) => {
    const timer = setTimeout(() => {
      pending.delete(String(id));
      rejectRequest(new Error(`timed out waiting for ${method}`));
    }, 30000);

    pending.set(String(id), {
      resolve: resolveRequest,
      reject: rejectRequest,
      timer,
    });
    send({ jsonrpc: "2.0", id, method, params });
  });
}

function modernMeta() {
  return {
    "io.modelcontextprotocol/protocolVersion": protocolVersion,
    "io.modelcontextprotocol/clientInfo": {
      name: "gopher-ai-tailwind-smoke",
      version: "1.0.0",
    },
    "io.modelcontextprotocol/clientCapabilities": {},
  };
}

try {
  const discovery = await request("discover", "server/discover", {
    _meta: modernMeta(),
  });

  let protocolMode;
  if (discovery.result) {
    assert(
      discovery.result.supportedVersions?.includes(protocolVersion),
      `server/discover did not advertise ${protocolVersion}`,
    );
    protocolMode = `modern MCP ${protocolVersion}`;
  } else {
    assert(discovery.error, "server/discover returned neither a result nor an error");
    assert(
      discovery.error.code !== -32022,
      `server is modern but does not support ${protocolVersion}`,
    );

    const initialization = await request("initialize", "initialize", {
      protocolVersion: legacyProtocolVersion,
      capabilities: {},
      clientInfo: {
        name: "gopher-ai-tailwind-smoke",
        version: "1.0.0",
      },
    });
    assert(
      initialization.result?.protocolVersion === legacyProtocolVersion,
      `legacy initialize did not negotiate ${legacyProtocolVersion}`,
    );
    send({
      jsonrpc: "2.0",
      method: "notifications/initialized",
      params: {},
    });
    protocolMode = `legacy MCP ${legacyProtocolVersion} fallback`;
  }

  const toolsResponse = await request(
    "tools",
    "tools/list",
    protocolMode.startsWith("modern") ? { _meta: modernMeta() } : {},
  );
  assert(toolsResponse.result?.tools, "tools/list did not return tools");

  const advertisedTools = new Set(
    toolsResponse.result.tools.map((tool) => tool.name),
  );
  const missingTools = requiredTools.filter((tool) => !advertisedTools.has(tool));
  assert(
    missingTools.length === 0,
    `tools/list is missing required tools: ${missingTools.join(", ")}`,
  );

  process.stdout.write(
    `PASS: ${packageSpec} used ${protocolMode} and advertised ${advertisedTools.size} tools (${requiredTools.length} required by the plugin).\n`,
  );
  if (discovery.error) {
    process.stdout.write(
      `SPEC: server/discover returned ${discovery.error.code}; ${protocolVersion} is not supported.\n`,
    );
  }
  if (nonProtocolLines.length > 0) {
    process.stdout.write(
      `NOTICE: server wrote ${nonProtocolLines.length} non-JSON line(s) to stdout before MCP responses.\n`,
    );
  }
} catch (error) {
  process.stderr.write(`FAIL: ${error.message}\n`);
  if (stderr.trim()) {
    process.stderr.write(stderr);
  }
  process.exitCode = 1;
} finally {
  child.stdin.end();
  if (process.exitCode) {
    child.kill();
  }
}
