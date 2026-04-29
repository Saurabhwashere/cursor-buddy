# AI Cursor Buddy

AI Cursor Buddy is a macOS AI companion that lives beside your cursor and helps people use websites and apps one safe step at a time.

It is designed for people who can feel overwhelmed by software: older adults, people with learning disabilities, people who are less confident with computers, or anyone who wants patient help while navigating a screen.

Hold `Option`, ask a question, and release. AI Cursor Buddy looks at the current screen, answers aloud, and can also do small low-risk Mac actions such as taking screenshots, copying URLs, saving page notes, and revealing files.

## What It Does

```text
User: How do I search for a video on YouTube?
AI Cursor Buddy: Click the search box at the top of the page.

User: I did that. What now?
AI Cursor Buddy: Type what you want to watch, then press Return.

User: Take a screenshot.
AI Cursor Buddy: Done. I saved the screenshot to your Desktop.

User: Where is it?
AI Cursor Buddy: I saved it here: /Users/.../Desktop/codex-cursor-screenshot.png
```

Core capabilities:

- Cursor-side voice companion that follows the mouse across apps, Spaces, full-screen windows, and monitors.
- Screen-aware step-by-step guidance from screenshots.
- Plain-English explanations and risk checks.
- Spoken answers with a compact `Speaking...` cursor bubble.
- Local task memory for follow-ups like `Where is it?`, `Open it`, `Try again`, and `Did it work?`.
- Direct low-risk Mac actions.
- Optional Codex CLI bridge for heavier work such as scripts, workflows, guides, and MCP scaffolds.

## Architecture

```text
Push-to-talk voice
-> Apple Speech transcript
-> ActionRouter
   -> memory follow-up
   -> low-risk Mac/browser action
   -> screen guidance
   -> risk check
   -> automation offer
   -> Codex action
-> response shown beside cursor and/or in the main panel
-> task memory updated
```

### macOS App

The app is a SwiftPM macOS SwiftUI executable in `app/`.

Important pieces:

- `AppState.swift`: coordinates voice, screenshots, routing, model calls, memory, and bridge actions.
- `ActionRouter.swift`: fast deterministic local router. It decides whether a request should go to memory, Mac action, Codex action, risk check, automation offer, or screen guidance.
- `CursorCompanionController.swift`: creates transparent overlay windows that keep the buddy next to the cursor.
- `VoiceInputService.swift`: push-to-talk microphone capture and Apple Speech recognition.
- `CodexClient.swift`: screen understanding through the OpenAI Responses API.
- `SpokenAnswerService.swift`: spoken answers through Realtime API, OpenAI TTS fallback, or macOS system voice.
- `InteractionMemoryStore.swift`: local JSON task ledger for follow-up questions.

### Cursor Overlay

AI Cursor Buddy uses one transparent `NSPanel` per display:

```text
one overlay window per screen
-> tracks NSEvent.mouseLocation
-> renders the buddy only on the screen containing the cursor
-> supports full-screen app Spaces
```

This is why the buddy can remain visible next to the cursor instead of behaving like a normal app window.

### Action Router

The app does not call a model for every routing decision. It first uses a fast local `ActionRouter`.

Examples:

```text
"Take a screenshot"                 -> Mac action
"Copy this page URL"                -> browser/Mac action
"Where is it?"                      -> memory lookup
"Open it"                           -> reveal latest artifact in Finder
"Create a Python script..."         -> Codex action
"How do I save this page..."        -> offer Codex automation or give steps
"Is this safe?"                     -> risk check
"What do I do next?"                -> screen guidance
```

This keeps common interactions quick and only wakes Codex when the task needs code, files, or a heavier workflow.

### Codex Bridge

The optional bridge is a local Node server in `bridge/server.mjs`.

It listens on:

```text
http://127.0.0.1:8765
```

The bridge can:

- Run `codex exec` in a generated workspace.
- Create scripts, guides, helper apps, or MCP server scaffolds.
- Perform a small set of low-risk local actions.
- Save audit metadata for each action.

Generated Codex workspaces are written to:

```text
generated-codex-tasks/
```

Local task memory is written to:

```text
generated-tools/memory/interaction-memory.json
```

These folders are ignored by Git.

## Models Used

### Screen Understanding

Default:

```text
gpt-5.4-nano
```

Used by `CodexClient` through the OpenAI Responses API. It receives:

- the user's question,
- compressed screenshot data,
- the selected mode,
- recent task memory.

Override:

```bash
OPENAI_MODEL=gpt-5.5
```

### Spoken Answers

Default:

```text
gpt-realtime-1.5
voice: marin
```

Used by `SpokenAnswerService` for natural spoken responses.

Fallback options:

- OpenAI TTS endpoint with `gpt-4o-mini-tts`.
- macOS system voice.

### Codex Bridge

Default:

```text
gpt-5.4-mini
```

Used by the Codex CLI bridge for generated scripts, guides, workflows, and MCP scaffolds.

Override:

```bash
CODEX_CURSOR_CODEX_MODEL=gpt-5.5
```

### Speech To Text

Push-to-talk currently uses Apple's `SFSpeechRecognizer`.

## Requirements

- macOS 13 or newer.
- Xcode command line tools / Swift toolchain.
- Node.js for the optional bridge.
- Codex CLI installed and authenticated if you want `Run with Codex` or `Make Repeatable`.
- OpenAI API key for real screen analysis and spoken OpenAI voices.

Install/check basics:

```bash
xcode-select --install
node --version
swift --version
codex --version
```

## Setup

Clone the repo:

```bash
git clone <your-repo-url>
cd codex-cursor
```

Set your OpenAI API key:

```bash
export OPENAI_API_KEY=your_key_here
```

Start the optional Codex Bridge in one terminal:

```bash
./scripts/run-bridge.sh
```

Start the macOS app in another terminal:

```bash
OPENAI_API_KEY=your_key_here ./scripts/run-app.sh
```

For a UI-only smoke test, you can omit `OPENAI_API_KEY`. The app will open, but screen analysis will show a setup error when you ask about a real screen.

## Permissions

macOS may ask for:

- **Screen Recording**: required for screenshot-based screen understanding.
- **Microphone**: required for push-to-talk.
- **Speech Recognition**: required for Apple Speech transcription.
- **Accessibility / Automation**: needed for some browser actions, especially Firefox URL reading.

After granting permissions, quit and relaunch the app.

The app panel includes setup status chips for API key, screen recording, microphone, and speech recognition.

## How To Use

1. Launch the bridge if you want Codex actions.
2. Launch the app.
3. Move to any website or app.
4. Hold `Option`.
5. Ask one question.
6. Release `Option`.

Useful prompts:

```text
What do I do next?
How do I search for a video on YouTube?
I did that. What now?
Explain this page simply.
Is this safe?
Take a screenshot.
Where is it?
Open it.
Copy this page URL.
What page am I on?
Save this page as Markdown notes.
Create a folder called "Receipts" on my Desktop.
Create a Python script to scrape this page.
Use Codex to create a simple guide for searching YouTube.
```

## Modes

The main panel supports four guidance modes:

- **Next Step**: one immediate practical action.
- **Explain**: plain-English explanation.
- **Checklist**: reusable checklist.
- **Risk Check**: trust, safety, official URLs, and sensitive-data warnings.

## Direct Actions

The bridge currently implements these direct low-risk actions:

- Take screenshot to Desktop.
- Save current browser page to Desktop as HTML or `.webloc`.
- Save current browser page as Markdown notes.
- Copy current browser URL.
- Report current browser page title and URL.
- Create a folder on Desktop.
- Reveal the latest saved file in Finder.

Browser support currently targets:

- Safari
- Firefox
- Google Chrome
- Microsoft Edge
- Brave Browser

The bridge is intentionally conservative. It should fail rather than silently use the wrong browser.

## Codex Actions

Use Codex for heavier work:

```text
Create a Python script to scrape this page.
Use Codex to make this workflow repeatable.
Use Codex to create a simple guide for searching YouTube.
Use Codex to scaffold an MCP server for this workflow.
```

Codex actions run in generated workspaces under:

```text
generated-codex-tasks/<task-id>/
```

The bridge asks Codex to keep generated code and docs inside that workspace.

## Environment Variables

```bash
# Required for real model calls
OPENAI_API_KEY=...

# Screen understanding model
OPENAI_MODEL=gpt-5.4-nano

# Max screenshot dimension before upload
CODEX_CURSOR_MAX_SCREENSHOT_DIMENSION=1280

# Spoken response provider: realtime, tts, or system
CODEX_CURSOR_TTS_PROVIDER=realtime

# Realtime speech
OPENAI_REALTIME_MODEL=gpt-realtime-1.5
OPENAI_REALTIME_VOICE=marin

# OpenAI TTS fallback
OPENAI_TTS_MODEL=gpt-4o-mini-tts
OPENAI_TTS_VOICE=marin

# Codex bridge
CODEX_CURSOR_BRIDGE_PORT=8765
CODEX_CURSOR_BRIDGE_URL=http://127.0.0.1:8765/codex-task
CODEX_CURSOR_CODEX_MODEL=gpt-5.4-mini
CODEX_BINARY=codex
```

## Build Only

Compile without launching:

```bash
swift build
```

Build and launch:

```bash
./scripts/run-app.sh
```

## Privacy And Safety

AI Cursor Buddy is intended to guide and assist, not to handle secrets.

Do not say passwords, one-time codes, payment details, private IDs, or health information aloud.

The current prototype:

- captures screenshots for screen analysis,
- stores local task memory in `generated-tools/memory`,
- stores generated Codex artifacts in `generated-codex-tasks`,
- keeps direct actions intentionally narrow.

High-risk actions such as submitting forms, deleting files, printing, sending messages, purchases, or account changes should require explicit confirmation before execution.

## Demo Story

Recommended demo arc:

1. Open YouTube.
2. Ask: `How do I search for a video on YouTube?`
3. Follow the next step.
4. Ask: `I did that. What now?`
5. Ask: `Explain this page simply.`
6. Ask: `Take a screenshot.`
7. Ask: `Where is it?`
8. Ask: `Open it.`
9. Ask: `Use Codex to create a simple guide for searching YouTube.`

This shows the core loop: understand, guide, act, remember, and extend through Codex.
