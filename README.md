# Codex Cursor

Codex Cursor is a macOS SwiftUI prototype for step-by-step help on any software screen.

When the app is running, a small Codex icon stays beside your cursor. Hold `Option` anywhere to speak a question, then release `Option` to submit it. Codex Cursor transcribes the question, analyzes the current screen, speaks the next practical step aloud, and, when useful, draws a temporary pointer over the relevant screen location.

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

Build and launch as a normal macOS app bundle:

```bash
OPENAI_API_KEY=your_key ./scripts/run-app.sh
```

For a UI-only smoke test, you can omit `OPENAI_API_KEY`. The app will open, but model analysis will show a missing key error when you click `Ask About This Screen`.

The command stays attached while the app is running. Close the app window or press `Control-C` in the terminal to stop it.

The first screenshot capture requires macOS screen recording permission. After granting permission in System Settings, reopen the app.

## Current MVP Loop

```text
Codex icon follows the cursor
-> hold Option
-> icon expands into a "Listening" bubble
-> speak a question
-> release Option
-> app briefly hides its own UI and captures the current screen
-> model returns one next step
-> answer is spoken aloud
-> app points to the relevant location
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
-> pressing Option expands the icon into a short "Ask me" label
```

This is intentionally different from moving a small app window around the screen. The overlay approach follows the cursor more smoothly across apps, spaces, and multiple monitors.

## Build Only

```bash
swift build
```

`swift build` only compiles the executable. It does not open the app window.
