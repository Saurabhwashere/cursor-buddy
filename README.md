# Codex Cursor

Codex Cursor is a macOS SwiftUI prototype for step-by-step help on any software screen.

When the app is running, a small Codex icon stays beside your cursor. Hold `Option` anywhere to speak a question, then release `Option` to submit it. Codex Cursor transcribes the question in a cursor-side bubble, analyzes the current screen, then shows and speaks the next practical step aloud.

Example flow:

```text
User presses Option.
User: How do I log into myGov?
Codex Cursor: Click the Sign in button in the top right.

User clicks it, presses Option again.
User: Okay, what now?
Codex Cursor: Use the official login form on this page. Keep your password and security codes private.
```

## Run

Start the optional Codex Bridge in one terminal if you want `Make Repeatable` to create local artifacts with Codex CLI:

```bash
./scripts/run-bridge.sh
```

Build and launch the macOS app in another terminal:

```bash
OPENAI_API_KEY=your_key ./scripts/run-app.sh
```

By default, screen understanding uses `gpt-5.4-nano` for low latency. For stronger reasoning, override it with `gpt-5.5`:

```bash
OPENAI_API_KEY=your_key OPENAI_MODEL=gpt-5.5 ./scripts/run-app.sh
```

Screenshots are downscaled to a max dimension of `1280px` and sent as JPEG for speed. You can tune this:

```bash
OPENAI_API_KEY=your_key CODEX_CURSOR_MAX_SCREENSHOT_DIMENSION=960 ./scripts/run-app.sh
```

By default, spoken answers use the Realtime API with `gpt-realtime-1.5` and the `marin` voice. You can override the realtime voice/model:

```bash
OPENAI_API_KEY=your_key OPENAI_REALTIME_VOICE=cedar ./scripts/run-app.sh
```

To force the older OpenAI speech endpoint instead:

```bash
OPENAI_API_KEY=your_key CODEX_CURSOR_TTS_PROVIDER=tts OPENAI_TTS_VOICE=cedar ./scripts/run-app.sh
```

To force the built-in macOS voice fallback:

```bash
CODEX_CURSOR_TTS_PROVIDER=system ./scripts/run-app.sh
```

For a UI-only smoke test, you can omit `OPENAI_API_KEY`. The app will open, but model analysis will show a missing key error when you click `Ask About This Screen`.

The command stays attached while the app is running. Close the app window or press `Control-C` in the terminal to stop it.

The first screenshot capture requires macOS screen recording permission. After granting permission in System Settings, reopen the app.
The panel shows status chips for API key, screen recording, microphone, and speech recognition so demo setup issues are visible.

Privacy note: Codex can guide you, but never say passwords, security codes, payment details, or private IDs aloud.

## Codex Bridge

The `Make Repeatable` button sends the latest screen prompt, answer, and screenshot path to a local bridge at `http://127.0.0.1:8765`.
The bridge runs `codex exec` in a generated workspace under `generated-codex-tasks/` and asks Codex to create a safe reusable artifact such as a guide, script, helper app, or MCP server scaffold.

Bridge defaults:

```bash
CODEX_CURSOR_CODEX_MODEL=gpt-5.4-mini
CODEX_CURSOR_BRIDGE_PORT=8765
```

## Current MVP Loop

```text
Codex icon follows the cursor
-> hold Option
-> icon expands into a cursor-side listening bubble
-> speak a question
-> transcript appears beside the cursor
-> release Option
-> app briefly hides its own UI and captures the current screen
-> buddy shows "Thinking..."
-> model returns one next step
-> answer appears beside the cursor and is spoken aloud
-> user does it
-> hold Option again for the next step
```

Checklist mode can still copy generated checklist Markdown to the clipboard or export it under `generated-tools/checklists`.
Use `Create Guide` after an analysis to preview a reusable Markdown guide, then save it with a manifest under `generated-tools/guides`. This is a stretch feature; the main demo should focus on the cursor-adjacent next-step loop.

## Cursor Companion Architecture

The cursor companion uses a Clicky-style overlay approach:

```text
one transparent full-screen overlay window per display
-> each overlay tracks NSEvent.mouseLocation at 60fps
-> only the overlay for the screen containing the cursor renders the Codex icon
-> pressing Option expands the icon into listening, thinking, answer, and speaking states
```

This is intentionally different from moving a small app window around the screen. The overlay approach follows the cursor more smoothly across apps, spaces, full-screen app Spaces, and multiple monitors. The app runs with accessory/agent-style activation so the buddy can remain visible over full-screen apps.

## Build Only

```bash
swift build
```

`swift build` only compiles the executable. It does not open the app window.
