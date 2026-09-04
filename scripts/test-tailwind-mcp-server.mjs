#!/usr/bin/env node

import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const capabilityMatrixPath = resolve(root, "docs/platform-capabilities.json");
const claudeManifestPath = resolve(root, "plugins/tailwind/.claude-plugin/plugin.json");
const mcpManifestPath = resolve(root, "plugins/tailwind/.mcp.json");
const protocolVersion = "2026-07-28";
const legacyProtocolVersion = "2024-11-05";
const responseTimeoutMs = 30000;

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

async function resolveServerLaunch(packageSpec) {
  const installRoot = process.env.TAILWIND_MCP_INSTALL_ROOT;
  if (!installRoot) {
    return {
      command: serverConfig.command,
      args: serverConfig.args,
      cwd: root,
    };
  }

  const versionSeparator = packageSpec.lastIndexOf("@");
  const packageName = packageSpec.slice(0, versionSeparator);
  const expectedVersion = packageSpec.slice(versionSeparator + 1);
  const packageRoot = resolve(installRoot, "node_modules", packageName);
  const installedPackage = await readJson(resolve(packageRoot, "package.json"));

  assert(
    installedPackage.version === expectedVersion,
    `preinstalled ${packageName} version ${installedPackage.version} does not match ${expectedVersion}`,
  );

  const binaryPath =
    typeof installedPackage.bin === "string"
      ? installedPackage.bin
      : installedPackage.bin?.["tailwindcss-server"];
  assert(binaryPath, `preinstalled ${packageName} does not declare tailwindcss-server`);

  return {
    command: process.execPath,
    args: [resolve(packageRoot, binaryPath)],
    cwd: root,
  };
}

const [capabilityMatrix, claudeManifest, mcpManifest] = await Promise.all([
  readJson(capabilityMatrixPath),
  readJson(claudeManifestPath),
  readJson(mcpManifestPath),
]);
const toolCapability = capabilityMatrix.capabilities?.find(
  (capability) => capability.id === "tailwind.supplementary-mcp-tools",
);
const toolPrefix = "mcp__tailwindcss__";
const declaredToolNames = toolCapability?.platforms?.codex?.names;

assert(
  Array.isArray(declaredToolNames) && declaredToolNames.length > 0,
  "capability matrix is missing the Tailwind MCP tool surface",
);
assert(
  declaredToolNames.every((name) => name.startsWith(toolPrefix)),
  "capability matrix contains a non-Tailwind MCP tool name",
);
const requiredTools = declaredToolNames.map((name) => name.slice(toolPrefix.length));
assert(
  new Set(requiredTools).size === requiredTools.length,
  "capability matrix contains duplicate Tailwind MCP tool names",
);
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

const serverLaunch = await resolveServerLaunch(packageSpec).catch((error) => {
  process.stderr.write(`FAIL: Tailwind MCP installation is not ready: ${error.message}\n`);
  process.exit(1);
});

const tempRoot =
  process.env.TMPDIR ?? process.env.TMP ?? process.env.TEMP ?? "/tmp";
const npmCache =
  process.env.npm_config_cache ??
  resolve(tempRoot, "gopher-ai-tailwind-mcp-npm-cache");
const child = spawn(serverLaunch.command, serverLaunch.args, {
  cwd: serverLaunch.cwd,
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
    }, responseTimeoutMs);

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

  const advertisedToolNames = toolsResponse.result.tools.map((tool) => tool.name);
  const advertisedTools = new Set(advertisedToolNames);
  assert(
    advertisedTools.size === advertisedToolNames.length,
    "tools/list returned duplicate tool names",
  );
  const missingTools = requiredTools.filter((tool) => !advertisedTools.has(tool));
  const unexpectedTools = [...advertisedTools].filter(
    (tool) => !requiredTools.includes(tool),
  );
  assert(
    missingTools.length === 0,
    `tools/list is missing required tools: ${missingTools.join(", ")}`,
  );
  assert(
    unexpectedTools.length === 0,
    `tools/list returned undeclared tools: ${unexpectedTools.join(", ")}`,
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
