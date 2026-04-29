import http from "node:http";
import { mkdir, writeFile, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";

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

  const directAction = await maybeRunDirectAction(body, workspace, taskId);
  if (directAction) {
    return directAction;
  }

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

async function maybeRunDirectAction(body, workspace, taskId) {
  const text = `${body.instruction || ""} ${body.prompt || ""}`.toLowerCase();
  const screenshotAction = await maybeRunScreenshotAction(text, workspace, taskId);
  if (screenshotAction) {
    return screenshotAction;
  }

  const desktopFolderAction = await maybeRunDesktopFolderAction(text, workspace, taskId);
  if (desktopFolderAction) {
    return desktopFolderAction;
  }

  const pageInfoAction = await maybeRunPageInfoAction(text, body, workspace, taskId);
  if (pageInfoAction) {
    return pageInfoAction;
  }

  const copyURLAction = await maybeRunCopyURLAction(text, body, workspace, taskId);
  if (copyURLAction) {
    return copyURLAction;
  }

  const markdownAction = await maybeRunMarkdownSaveAction(text, body, workspace, taskId);
  if (markdownAction) {
    return markdownAction;
  }

  const wantsPageSave = body.mode === "action"
    && body.profile === "browser"
    && /\b(download|save|export|capture)\b/.test(text)
    && /\bdesktop\b/.test(text);

  if (!wantsPageSave) {
    return null;
  }

  const browserPage = await getFrontBrowserPage(body);
  if (!browserPage.url) {
    throw new Error("I could not read the current browser URL. Bring Safari, Firefox, Chrome, Edge, or Brave to the front and try again.");
  }

  const desktopDir = path.join(homedir(), "Desktop");
  const filenameBase = slug(browserPage.title || new URL(browserPage.url).hostname || "saved-page");
  const htmlPath = uniqueDesktopPath(desktopDir, `${filenameBase}.html`);
  const metadataPath = path.join(workspace, "saved-page.json");

  let savedPath = htmlPath;
  let savedKind = "HTML snapshot";
  let note = "Saved the current page HTML to Desktop.";

  try {
    const pageResponse = await fetch(browserPage.url, {
      redirect: "follow",
      headers: {
        "user-agent": "Mozilla/5.0 CodexCursor/1.0"
      }
    });

    if (!pageResponse.ok) {
      throw new Error(`HTTP ${pageResponse.status}`);
    }

    const html = await pageResponse.text();
    await writeFile(htmlPath, html);
  } catch (error) {
    savedKind = "web location shortcut";
    savedPath = uniqueDesktopPath(desktopDir, `${filenameBase}.webloc`);
    note = "I could not fetch the full page HTML, so I saved a Desktop web location shortcut instead.";
    await writeFile(savedPath, [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
      "<plist version=\"1.0\">",
      "<dict>",
      "  <key>URL</key>",
      `  <string>${escapeXML(browserPage.url)}</string>`,
      "</dict>",
      "</plist>",
      ""
    ].join("\n"));
  }

  await writeFile(metadataPath, JSON.stringify({
    action: "save-current-browser-page-to-desktop",
    browser: browserPage.browser,
    title: browserPage.title,
    url: browserPage.url,
    savedPath,
    savedKind,
    note
  }, null, 2));

  return {
    taskId,
    workspace,
    finalMessage: [
      `${note}`,
      "",
      `Saved as: ${savedPath}`,
      `Source: ${browserPage.url}`,
      `Browser: ${browserPage.browser || "front browser"}`,
      "",
      `Audit metadata: ${metadataPath}`
    ].join("\n"),
    stdout: "",
    stderr: "",
    exitCode: 0
  };
}

async function maybeRunPageInfoAction(text, body, workspace, taskId) {
  const wantsPageInfo = /\b(what page am i on|what website am i on|what url am i on|what is this page|where am i on the web)\b/.test(text);
  if (!wantsPageInfo) {
    return null;
  }

  const browserPage = await getFrontBrowserPage(body);
  const metadataPath = path.join(workspace, "current-page.json");
  await writeFile(metadataPath, JSON.stringify({
    action: "get-current-browser-page",
    browser: browserPage.browser,
    title: browserPage.title,
    url: browserPage.url
  }, null, 2));

  return {
    taskId,
    workspace,
    finalMessage: [
      `You are on: ${browserPage.title || browserPage.url}`,
      `URL: ${browserPage.url}`,
      `Browser: ${browserPage.browser || "front browser"}`,
      "",
      `Audit metadata: ${metadataPath}`
    ].join("\n"),
    stdout: "",
    stderr: "",
    exitCode: 0
  };
}

async function maybeRunCopyURLAction(text, body, workspace, taskId) {
  const wantsCopyURL = /\b(copy|put)\b/.test(text)
    && /\b(url|link|current page|this page)\b/.test(text)
    && /\bclipboard|copy\b/.test(text);

  if (!wantsCopyURL) {
    return null;
  }

  const browserPage = await getFrontBrowserPage(body);
  const metadataPath = path.join(workspace, "copied-url.json");
  await runProcess("pbcopy", [], browserPage.url, 5_000);
  await writeFile(metadataPath, JSON.stringify({
    action: "copy-current-browser-url",
    browser: browserPage.browser,
    title: browserPage.title,
    url: browserPage.url
  }, null, 2));

  return {
    taskId,
    workspace,
    finalMessage: [
      "Copied the current page URL to your clipboard.",
      "",
      `URL: ${browserPage.url}`,
      `Browser: ${browserPage.browser || "front browser"}`,
      "",
      `Audit metadata: ${metadataPath}`
    ].join("\n"),
    stdout: "",
    stderr: "",
    exitCode: 0
  };
}

async function maybeRunMarkdownSaveAction(text, body, workspace, taskId) {
  const wantsMarkdown = /\b(save|export|capture)\b/.test(text)
    && /\b(markdown|notes|md)\b/.test(text)
    && /\b(page|webpage|website|site|browser|url|this)\b/.test(text);

  if (!wantsMarkdown) {
    return null;
  }

  const browserPage = await getFrontBrowserPage(body);
  const desktopDir = path.join(homedir(), "Desktop");
  const filenameBase = slug(browserPage.title || new URL(browserPage.url).hostname || "page-notes");
  const savedPath = uniqueDesktopPath(desktopDir, `${filenameBase}.md`);
  const metadataPath = path.join(workspace, "saved-page-markdown.json");
  let pageText = "";
  let note = "Saved the current page as Markdown notes on Desktop.";

  try {
    const pageResponse = await fetch(browserPage.url, {
      redirect: "follow",
      headers: {
        "user-agent": "Mozilla/5.0 CodexCursor/1.0"
      }
    });

    if (!pageResponse.ok) {
      throw new Error(`HTTP ${pageResponse.status}`);
    }

    const html = await pageResponse.text();
    pageText = htmlToText(html).slice(0, 30_000);
  } catch (error) {
    note = "Saved Markdown notes with the URL because I could not fetch the full page text.";
  }

  const markdown = [
    `# ${browserPage.title || "Saved page"}`,
    "",
    `Source: ${browserPage.url}`,
    `Browser: ${browserPage.browser || "front browser"}`,
    "",
    pageText ? "## Extracted text" : "## Note",
    "",
    pageText || "The page could not be fetched directly. Open the source URL above to view it."
  ].join("\n");
  await writeFile(savedPath, markdown);
  await writeFile(metadataPath, JSON.stringify({
    action: "save-current-page-as-markdown",
    browser: browserPage.browser,
    title: browserPage.title,
    url: browserPage.url,
    savedPath,
    savedKind: "Markdown notes",
    note
  }, null, 2));

  return {
    taskId,
    workspace,
    finalMessage: [
      note,
      "",
      `Saved as: ${savedPath}`,
      `Source: ${browserPage.url}`,
      `Browser: ${browserPage.browser || "front browser"}`,
      "",
      `Audit metadata: ${metadataPath}`
    ].join("\n"),
    stdout: "",
    stderr: "",
    exitCode: 0
  };
}

async function maybeRunDesktopFolderAction(text, workspace, taskId) {
  const wantsFolder = /\b(create|make|new)\b/.test(text)
    && /\b(folder|directory)\b/.test(text)
    && /\bdesktop\b/.test(text);

  if (!wantsFolder) {
    return null;
  }

  const desktopDir = path.join(homedir(), "Desktop");
  const requestedName = extractQuotedName(text) || "Codex Cursor Folder";
  const folderPath = uniqueDesktopPath(desktopDir, slugHuman(requestedName));
  const metadataPath = path.join(workspace, "desktop-folder.json");
  await mkdir(folderPath, { recursive: true });
  await writeFile(metadataPath, JSON.stringify({
    action: "create-desktop-folder",
    folderPath
  }, null, 2));

  return {
    taskId,
    workspace,
    finalMessage: [
      "Created a folder on your Desktop.",
      "",
      `Saved as: ${folderPath}`,
      "",
      `Audit metadata: ${metadataPath}`
    ].join("\n"),
    stdout: "",
    stderr: "",
    exitCode: 0
  };
}

async function maybeRunScreenshotAction(text, workspace, taskId) {
  const wantsScreenshot = /\b(screenshot|screen shot|capture screen|capture my screen|take a picture of (my )?screen)\b/.test(text)
    && !/\b(script|python|code|program)\b/.test(text);

  if (!wantsScreenshot) {
    return null;
  }

  const desktopDir = path.join(homedir(), "Desktop");
  const savedPath = uniqueDesktopPath(desktopDir, `codex-cursor-screenshot-${timestampForFilename()}.png`);
  const metadataPath = path.join(workspace, "screenshot.json");
  const { stderr, code } = await runProcess("screencapture", ["-x", savedPath], "", 20_000);

  if (code !== 0) {
    throw new Error([
      "I could not take the screenshot.",
      "macOS may need Screen Recording permission for the terminal app running the bridge.",
      stderr.trim() ? `Details: ${stderr.trim()}` : ""
    ].filter(Boolean).join(" "));
  }

  await writeFile(metadataPath, JSON.stringify({
    action: "take-screenshot-to-desktop",
    savedPath,
    savedKind: "PNG screenshot",
    note: "Saved a screenshot to Desktop."
  }, null, 2));

  return {
    taskId,
    workspace,
    finalMessage: [
      "Saved a screenshot to Desktop.",
      "",
      `Saved as: ${savedPath}`,
      "",
      `Audit metadata: ${metadataPath}`
    ].join("\n"),
    stdout: "",
    stderr: "",
    exitCode: 0
  };
}

async function getFrontBrowserPage(body = {}) {
  const requestedBrowser = browserFromActiveApplication(body.activeApplication);
  if (requestedBrowser) {
    return getBrowserPageStrict(requestedBrowser);
  }

  const frontAppAttempt = await tryGetFrontBrowserPage();
  if (frontAppAttempt.page?.url) {
    return frontAppAttempt.page;
  }

  const frontApp = frontAppAttempt.page?.browser || await getFrontAppName();
  if (frontApp === "Firefox") {
    const firefoxPage = await getFirefoxPage();
    if (firefoxPage.url) {
      return firefoxPage;
    }
  }

  if (isKnownBrowser(frontApp)) {
    throw new Error([
      `The front app is ${frontApp}, but I could not read its current URL.`,
      "I will not fall back to another browser because that could save the wrong page.",
      frontAppAttempt.error ? `Details: ${frontAppAttempt.error}` : ""
    ].filter(Boolean).join(" "));
  }

  const details = [
    frontAppAttempt.error ? `Front app check failed: ${frontAppAttempt.error}` : ""
  ].filter(Boolean).join(" | ");

  throw new Error([
    "I could not read a browser URL from Safari, Firefox, Chrome, Edge, or Brave.",
    "Bring the browser window to the front and try again.",
    "If macOS asks for Automation permission, allow the terminal app running the bridge to control your browser.",
    "I will not guess by scanning another browser because that can save the wrong page.",
    details ? `Details: ${details}` : ""
  ].filter(Boolean).join(" "));
}

async function getBrowserPageStrict(browser) {
  if (browser.name === "Firefox") {
    const firefoxPage = await getFirefoxPage();
    if (firefoxPage.url) {
      return firefoxPage;
    }

    throw new Error("Firefox is the intended browser, but I could not read its address bar URL.");
  }

  const page = await getBrowserPage(browser);
  if (page.url) {
    return page;
  }

  throw new Error(`${browser.name} is the intended browser, but I could not read its current URL.`);
}

async function tryGetFrontBrowserPage() {
  const script = `
set frontApp to ""
set pageTitle to ""
set pageUrl to ""
tell application "System Events"
  set frontApp to name of first application process whose frontmost is true
end tell

if frontApp is "Safari" then
  tell application "Safari"
    set pageTitle to name of current tab of front window
    set pageUrl to URL of current tab of front window
  end tell
else if frontApp is "Google Chrome" then
  tell application "Google Chrome"
    set pageTitle to title of active tab of front window
    set pageUrl to URL of active tab of front window
  end tell
else if frontApp is "Microsoft Edge" then
  tell application "Microsoft Edge"
    set pageTitle to title of active tab of front window
    set pageUrl to URL of active tab of front window
  end tell
else if frontApp is "Brave Browser" then
  tell application "Brave Browser"
    set pageTitle to title of active tab of front window
    set pageUrl to URL of active tab of front window
  end tell
else if frontApp is "Firefox" then
  set pageTitle to "Firefox page"
end if

return frontApp & "\\n" & pageTitle & "\\n" & pageUrl
`.trim();

  try {
    return { page: parseBrowserPage(await runAppleScript(script)) };
  } catch (error) {
    return {
      page: null,
      error: error instanceof Error ? error.message : String(error)
    };
  }
}

async function getFrontAppName() {
  const script = `
tell application "System Events"
  return name of first application process whose frontmost is true
end tell
`.trim();

  try {
    return (await runAppleScript(script)).trim();
  } catch {
    return "";
  }
}

async function getFirefoxPage() {
  const script = `
set previousClipboard to the clipboard
set pageTitle to "Firefox page"
set pageUrl to ""
tell application "Firefox" to activate
delay 0.15
tell application "System Events"
  keystroke "l" using command down
  delay 0.05
  keystroke "c" using command down
  delay 0.05
end tell
set pageUrl to the clipboard
set the clipboard to previousClipboard
return "Firefox" & "\\n" & pageTitle & "\\n" & pageUrl
`.trim();

  return parseBrowserPage(await runAppleScript(script));
}

async function getBrowserPage(browser) {
  const script = `
tell application "${browser.app}"
  set pageTitle to ${browser.titleExpression}
  set pageUrl to ${browser.urlExpression}
end tell
return "${browser.name}" & "\\n" & pageTitle & "\\n" & pageUrl
`.trim();

  return parseBrowserPage(await runAppleScript(script));
}

function browserTargets() {
  return [
    {
      name: "Safari",
      app: "Safari",
      titleExpression: "name of current tab of front window",
      urlExpression: "URL of current tab of front window"
    },
    {
      name: "Google Chrome",
      app: "Google Chrome",
      titleExpression: "title of active tab of front window",
      urlExpression: "URL of active tab of front window"
    },
    {
      name: "Microsoft Edge",
      app: "Microsoft Edge",
      titleExpression: "title of active tab of front window",
      urlExpression: "URL of active tab of front window"
    },
    {
      name: "Brave Browser",
      app: "Brave Browser",
      titleExpression: "title of active tab of front window",
      urlExpression: "URL of active tab of front window"
    }
  ];
}

function browserFromActiveApplication(activeApplication = {}) {
  const name = String(activeApplication.name || "");
  const bundleIdentifier = String(activeApplication.bundleIdentifier || "");
  const haystack = `${name} ${bundleIdentifier}`.toLowerCase();

  if (haystack.includes("firefox")) {
    return { name: "Firefox", app: "Firefox" };
  }

  return browserTargets().find(browser => {
    const browserName = browser.name.toLowerCase();
    const appName = browser.app.toLowerCase();
    return haystack.includes(browserName) || haystack.includes(appName);
  }) || null;
}

function isKnownBrowser(appName) {
  return [
    "Safari",
    "Firefox",
    "Google Chrome",
    "Microsoft Edge",
    "Brave Browser"
  ].includes(appName);
}

function parseBrowserPage(stdout) {
  const [browser = "", title = "", ...urlParts] = stdout.trim().split("\n");
  return {
    browser: browser.trim(),
    title: title.trim(),
    url: urlParts.join("\n").trim()
  };
}

async function runAppleScript(script) {
  const args = script.split("\n").flatMap(line => ["-e", line]);
  const { stdout, stderr, code } = await runProcess("osascript", args, "", 10_000);

  if (code !== 0) {
    throw new Error(stderr.trim() || `osascript exited with code ${code}`);
  }

  return stdout;
}

function uniqueDesktopPath(directory, filename) {
  const extension = path.extname(filename);
  const base = path.basename(filename, extension);
  let candidate = path.join(directory, filename);
  let index = 2;

  while (existsSync(candidate)) {
    candidate = path.join(directory, `${base}-${index}${extension}`);
    index += 1;
  }

  return candidate;
}

function slug(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64) || "saved-page";
}

function slugHuman(value) {
  const clean = String(value)
    .trim()
    .replace(/[/:\\]/g, "-")
    .replace(/\s+/g, " ")
    .slice(0, 64);
  return clean || "Codex Cursor Folder";
}

function extractQuotedName(text) {
  const quoted = text.match(/["']([^"']+)["']/);
  if (quoted?.[1]) {
    return quoted[1];
  }

  const called = text.match(/\b(?:called|named)\s+([a-z0-9 _-]+)/i);
  return called?.[1]?.trim();
}

function htmlToText(html) {
  return String(html)
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/\s+\n/g, "\n")
    .replace(/\n\s+/g, "\n")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function timestampForFilename() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function escapeXML(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function buildPrompt(body, workspace) {
  if (body.mode === "action") {
    return buildActionPrompt(body, workspace);
  }

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

function buildActionPrompt(body, workspace) {
  const profile = body.profile || "general";
  const profileGuidance = {
    browser: `
Browser-control profile:
- Interpret the visible browser/page context from the screenshot and prompt.
- Prefer creating a safe local helper under this workspace, such as a Playwright script, AppleScript, Markdown runbook, or MCP tool scaffold.
- For print, submit, payment, account, login, deletion, or irreversible actions, stop at a clear confirmation step. Do not execute the final action.
- If automation is appropriate, create the script and document the exact command the user should run after confirming.
`,
    mcp: `
MCP profile:
- Create a minimal MCP server scaffold or tool design only when it helps the user's request.
- Keep the scaffold local to this workspace.
- Include install/run instructions and a short example tool call.
`,
    files: `
Files profile:
- Create the requested local document, script, checklist, or helper file inside this workspace.
- Do not modify files outside this workspace.
`,
    mac: `
Mac-control profile:
- Prefer AppleScript or Shortcuts-compatible snippets saved inside this workspace.
- Do not run GUI automation or final OS actions. Provide a confirmation checklist and exact next command.
`,
    general: `
General action profile:
- Create the safest useful local artifact or action plan inside this workspace.
- If a real-world or OS action is involved, stop at confirmation and explain the next step.
`
  }[profile] || "";

  return `
You are Codex running from Codex Cursor.

Codex Cursor is a voice-and-screen companion. The user asked it to hand an action to Codex.
Work in this generated workspace only:
${workspace}

Action mode: ${body.mode || "action"}
Tool profile: ${profile}

${profileGuidance}

Hard safety rules:
- Never request, store, reveal, or submit passwords, OTPs, payment details, private IDs, or secrets.
- Never submit forms, print, purchase, delete, message, upload, or change account settings without an explicit final confirmation from the user.
- Keep all generated code, docs, and outputs inside the current workspace.
- If the requested action needs permissions unavailable from this sandbox, create the safest runnable artifact and explain what permission or manual confirmation is needed.
- Be useful and concrete: write files, scripts, or scaffolds when that is safer than only explaining.

User action request:
${body.instruction || body.prompt || "(none)"}

Latest spoken prompt:
${body.prompt || "(none)"}

Latest assistant answer, if any:
${body.answer || "(none)"}

Latest suggested steps, if any:
${JSON.stringify(body.steps || [], null, 2)}

Risk warnings, if any:
${JSON.stringify(body.riskWarnings || [], null, 2)}

Visible screen metadata:
${JSON.stringify(body.screen || {}, null, 2)}

Final response requirements:
1. Say what you created or prepared.
2. Give the workspace path.
3. Give the exact next command or user confirmation needed.
4. If the request was unsafe to execute directly, say what was intentionally not executed.
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
