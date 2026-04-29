import http from "node:http";
import { mkdir, writeFile, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");
const port = Number(process.env.CODEX_CURSOR_BRIDGE_PORT || 8765);
const codexBinary = process.env.CODEX_BINARY || "codex";
const codexModel = process.env.CODEX_CURSOR_CODEX_MODEL || "gpt-5.4-mini";

const server = http.createServer(async (request, response) => {
  if (request.method === "GET" && request.url === "/health") {
    sendJSON(response, 200, { ok: true });
    return;
  }

  if (request.method !== "POST" || request.url !== "/codex-task") {
    sendJSON(response, 404, { ok: false, error: "Not found" });
    return;
  }

  try {
    const body = await readJSON(request);
    const result = await runCodexTask(body);
    sendJSON(response, 200, { ok: true, ...result });
  } catch (error) {
    sendJSON(response, 500, {
      ok: false,
      error: error instanceof Error ? error.message : String(error)
    });
  }
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Codex Cursor bridge listening at http://127.0.0.1:${port}`);
});

async function runCodexTask(body) {
  const taskId = new Date().toISOString().replace(/[:.]/g, "-");
  const workspace = path.join(repoRoot, "generated-codex-tasks", taskId);
  const outputPath = path.join(workspace, "codex-final.md");
  const contextPath = path.join(workspace, "context.json");

  await mkdir(workspace, { recursive: true });
  await writeFile(contextPath, JSON.stringify(body, null, 2));

  const prompt = buildPrompt(body, workspace);
  const args = [
    "exec",
    "--cd", workspace,
    "--skip-git-repo-check",
    "--sandbox", "workspace-write",
    "--ask-for-approval", "never",
    "--model", body.model || codexModel,
    "--output-last-message", outputPath
  ];

  if (body.screenshotPath && existsSync(body.screenshotPath)) {
    args.push("--image", body.screenshotPath);
  }

  args.push("-");

  const { stdout, stderr, code } = await runProcess(codexBinary, args, prompt, 5 * 60 * 1000);
  const finalMessage = existsSync(outputPath)
    ? await readFile(outputPath, "utf8")
    : stdout.trim();

  return {
    taskId,
    workspace,
    finalMessage: finalMessage.trim(),
    stdout: stdout.trim().slice(-4000),
    stderr: stderr.trim().slice(-4000),
    exitCode: code
  };
}

function buildPrompt(body, workspace) {
  return `
You are Codex running from Codex Cursor.

The user is asking to make their current screen/workflow repeatable. Create a useful local artifact in this workspace:
${workspace}

Prefer one of these outputs depending on the context:
- a Markdown guide/checklist
- a small script
- a tiny local helper app
- a scaffolded MCP server if the request clearly needs Codex/tool integration

Safety rules:
- Do not submit forms or automate sensitive actions.
- Do not request or store passwords, OTPs, payment details, private IDs, or secrets.
- Keep generated code and docs inside the current workspace.
- If a browser automation or MCP server would be useful, scaffold it but keep it safe and documented.

User instruction:
${body.instruction || "Make this workflow repeatable."}

Latest spoken prompt:
${body.prompt || "(none)"}

Latest assistant answer:
${body.answer || "(none)"}

Visible screen metadata:
${JSON.stringify(body.screen || {}, null, 2)}

Write a concise final summary listing:
1. what you created
2. where it lives
3. how to run or use it
`.trim();
}

function readJSON(request) {
  return new Promise((resolve, reject) => {
    let body = "";
    request.on("data", chunk => {
      body += chunk;
      if (body.length > 2_000_000) {
        request.destroy();
        reject(new Error("Request body too large"));
      }
    });
    request.on("end", () => {
      try {
        resolve(JSON.parse(body || "{}"));
      } catch {
        reject(new Error("Invalid JSON"));
      }
    });
    request.on("error", reject);
  });
}

function runProcess(command, args, stdin, timeoutMs) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: repoRoot,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"]
    });

    let stdout = "";
    let stderr = "";
    let settled = false;
    const timeout = setTimeout(() => {
      if (!settled) {
        child.kill("SIGTERM");
        reject(new Error("Codex task timed out"));
      }
    }, timeoutMs);

    child.stdout.on("data", chunk => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", chunk => {
      stderr += chunk.toString();
    });
    child.on("error", error => {
      clearTimeout(timeout);
      settled = true;
      reject(error);
    });
    child.on("close", code => {
      clearTimeout(timeout);
      settled = true;
      resolve({ stdout, stderr, code });
    });
    child.stdin.end(stdin);
  });
}

function sendJSON(response, statusCode, object) {
  response.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-origin": "http://127.0.0.1"
  });
  response.end(JSON.stringify(object));
}
