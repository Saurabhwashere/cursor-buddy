# Codex Cursor Build Plan

## Current Direction

The hackathon version is now intentionally narrower:

```text
Option key
-> Codex companion appears beside the cursor
-> user asks one question about the current screen
-> Codex gives one clear next step
-> Codex points at the relevant screen location
-> user does it
-> press Option again for "what now?"
```

Tool generation, reusable guides, voice, and automation are stretch goals. The main demo should prove that Codex can live next to the cursor and guide a user through confusing software one step at a time.

## Product Summary

Build a macOS screen-aware Codex companion.

The app lets a user press a hotkey, capture their current screen, ask a question, and receive a plain-English explanation with step-by-step guidance and visual pointer overlays. The longer-term differentiator is that Codex can turn repeated workflows into reusable checklists, guides, scripts, or local tools.

Core pitch:

> Codex Cursor is a screen-aware assistant for people stuck inside confusing software. It sees the interface, explains it in plain language, points to what matters, and can turn repeated workflows into reusable tools.

## Hackathon MVP Goal

Build this loop:

```text
Press hotkey
-> capture screenshot
-> ask "What do I do next?"
-> model analyzes screenshot
-> floating overlay shows answer
-> overlay points to relevant screen location
-> user can generate a checklist/guide from the current task
```

Do not build voice or full automation first.

## Version Roadmap

### Version 0: Mac App Shell

Goal: working native shell with visible companion UI.

Features:

- macOS SwiftUI app
- menu bar icon
- floating overlay/panel
- text input
- submit button
- fake placeholder response
- close/minimize controls
- global hotkey, if time allows in this version

Tasks:

1. Create macOS SwiftUI project.
2. Configure app as menu bar utility if possible.
3. Add `AppState`.
4. Add `CompanionPanel` view.
5. Add text field for prompt.
6. Add response display.
7. Add loading and error states.
8. Add a fake local response so UI can be tested without model calls.

Acceptance criteria:

- App launches.
- A floating panel can be shown.
- User can type a question.
- Pressing submit shows a fake response.

### Version 1: Screenshot And Screen-Aware Answer

Goal: capture screen and send screenshot plus prompt to a vision model.

Features:

- screenshot capture
- screen recording permission handling
- send screenshot plus prompt to local model client
- show plain-English answer
- show steps

Suggested files:

```text
app/
  CodexCursorApp.swift
  AppState.swift
  Views/
    CompanionPanel.swift
    ResponseView.swift
  Services/
    ScreenshotService.swift
    CodexClient.swift
```

Model response schema:

```json
{
  "answer": "This page is asking for your student ID.",
  "steps": [
    "Click the Student ID field.",
    "Enter the student ID from your email.",
    "Press Continue."
  ],
  "points": [
    {
      "x": 742,
      "y": 418,
      "label": "Student ID field"
    }
  ],
  "riskWarnings": []
}
```

System prompt:

```text
You are Codex Cursor, a screen-aware assistant.

Given a screenshot and the user's question:
1. Explain the screen in plain English.
2. Tell the user the next 1-3 actions.
3. If useful, identify one screen location to point at.

Return JSON:
{
  "answer": string,
  "steps": string[],
  "points": [
    { "x": number, "y": number, "label": string }
  ],
  "riskWarnings": string[]
}

Coordinates must be pixel coordinates relative to the screenshot.
If you are unsure, return an empty points array.
Do not ask the user to enter sensitive information like passwords, payment details, private keys, payment card numbers, or one-time codes.
If the screen appears to involve high-stakes financial, legal, medical, or government decisions, explain carefully and recommend verifying with an official source or qualified person.
```

Tasks:

1. Implement full-screen screenshot capture.
2. Save latest screenshot to temporary local path.
3. Add screen recording permission handling.
4. Implement `CodexClient`.
5. Send prompt plus screenshot to model.
6. Parse JSON response.
7. Display `answer`, `steps`, and warnings.
8. Add graceful fallback if response is not valid JSON.

Acceptance criteria:

- User can capture screen.
- User can ask a question about it.
- App displays a real model answer.
- App displays 1-3 steps.

### Version 2: Pointer Overlay

Goal: show visual markers on top of the user's screen.

Features:

- transparent overlay window
- pointer dot/halo
- label near point
- coordinate mapping from screenshot to screen
- support one or more points

Suggested files:

```text
app/
  Views/
    PointerOverlay.swift
  Services/
    CoordinateMapper.swift
```

Tasks:

1. Create transparent always-on-top overlay window.
2. Draw circular marker at returned point.
3. Draw small label next to marker.
4. Convert screenshot coordinates to display coordinates.
5. Handle Retina scale factor correctly.
6. Hide overlay when no point exists.
7. Add timeout or dismiss button.

Acceptance criteria:

- Model returns a point.
- App draws marker on the matching screen location.
- Marker disappears when dismissed.

### Version 3: Guidance Modes

Goal: make the app useful and demo-friendly.

Modes:

- `What do I do next?`
- `Explain in plain English`
- `Make a checklist`
- `Risk check`

Tasks:

1. Add mode selector buttons.
2. Change prompt instructions based on selected mode.
3. For checklist mode, return a structured checklist:

```json
{
  "title": "Before you start this form",
  "items": [
    "Have your student ID ready.",
    "Prepare your passport or license.",
    "Check the deadline."
  ]
}
```

4. Add copy-to-clipboard for checklist.
5. Add export to Markdown.

Acceptance criteria:

- User can pick a mode.
- Each mode produces a noticeably different useful response.
- Checklist can be copied/exported.

### Version 4: Toolsmith Slice

Goal: make it uniquely Codex by generating reusable local helpers.

For the hackathon, start with safe generated artifacts:

- Markdown guide
- checklist
- small local HTML helper
- optional script only after review

Features:

- "Create reusable guide" button
- saves generated artifact locally
- shows generated content before saving
- opens generated artifact in app panel or Finder

Suggested directory:

```text
generated-tools/
  guides/
  checklists/
  scripts/
```

Tool manifest:

```json
{
  "name": "student-form-checklist",
  "type": "guide",
  "description": "Checklist for completing the student registration form.",
  "createdAt": "2026-04-29T00:00:00Z",
  "source": "screen-analysis"
}
```

Tasks:

1. Add `GeneratedArtifact` model.
2. Add "Create Guide" command.
3. Generate Markdown from current screenshot plus response.
4. Preview generated guide.
5. Save guide under `generated-tools/guides`.
6. Add manifest JSON.
7. Optional: add "Reveal in Finder".

Acceptance criteria:

- From a confusing screen, user can generate a reusable guide.
- Guide is saved locally.
- User can review it before saving.

## Suggested Architecture

### App Modules

```text
AppState
- current prompt
- selected mode
- latest screenshot
- latest response
- loading/error state
- active pointer points

ScreenshotService
- request permissions
- capture screen
- save image
- return image data and dimensions

CodexClient
- prepare prompt
- send screenshot and text
- parse structured response

OverlayController
- manages companion panel window
- manages pointer overlay window

CoordinateMapper
- converts screenshot coordinates to screen coordinates

ArtifactService
- creates and saves guides/checklists/tools
```

### Data Models

```swift
struct ScreenAnalysisResponse: Codable {
    let answer: String
    let steps: [String]
    let points: [PointerPoint]
    let riskWarnings: [String]
}

struct PointerPoint: Codable, Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
    let label: String
}

enum GuidanceMode: String, CaseIterable {
    case nextStep
    case plainEnglish
    case checklist
    case riskCheck
}
```

## Optional Local Server

If easier than calling the model from Swift directly, add a small local TypeScript server:

```text
server/
  src/
    index.ts
    analyzeScreen.ts
    schemas.ts
```

Endpoints:

```text
POST /analyze-screen
POST /generate-guide
```

Benefits:

- easier model API integration
- easier JSON schema validation
- keeps Swift app simpler
- can later become MCP server

## Later MCP Direction

After the hackathon MVP works, wrap the backend as an MCP server.

MCP tools:

```ts
analyze_current_screen({ prompt, mode })
get_latest_screen_context()
create_reusable_guide()
create_local_tool()
list_generated_tools()
run_generated_tool_with_approval()
```

This lets Codex Desktop interact with the screen assistant and generated artifacts.

## Safety Rules

Implement from the beginning:

```text
- Do not submit forms automatically.
- Do not ask for or process passwords, private keys, payment card numbers, or one-time codes.
- Before any action that changes user data, ask for confirmation.
- Keep screenshots local unless explicitly sent for analysis.
- Show a visible indicator when a screenshot is captured.
- Generated scripts must be previewed before running.
- Never auto-run generated code.
```

## Hackathon Demo Script

### Demo 1: Confusing Form Helper

1. Open a complicated form or demo webpage.
2. Press hotkey.
3. Ask:

```text
What should I do next?
```

4. App explains the screen.
5. App points to the relevant field/button.
6. Switch to checklist mode.
7. App creates a checklist.

### Demo 2: Toolsmith Moment

1. Ask:

```text
Turn this into a reusable guide for next time.
```

2. App generates a Markdown guide.
3. User previews and saves it.
4. Show generated file.

### Demo Pitch

```text
Codex Cursor is a screen-aware assistant for people stuck inside confusing software.

It sees your screen, explains the interface in plain English, points to the next action, and turns repeated workflows into reusable tools.

This is not just chat beside your computer. It is Codex becoming a toolsmith for your everyday workflows.
```

## Build Order

1. Mac shell with fake response.
2. Screenshot capture.
3. Model call with screenshot.
4. Structured response display.
5. Pointer overlay.
6. Guidance modes.
7. Checklist/guide generation.
8. Polish demo UI.
9. Prepare demo page and backup video.
10. Only then consider voice or automation.

## What Not To Build First

Do not build these until the core loop works:

```text
- voice conversation
- autonomous clicking
- password/form filling
- arbitrary app control
- complex workflow recording
- full MCP tool ecosystem
- multi-agent orchestration
```

## Definition Of Done For MVP

The project is demo-ready when:

```text
- A user can press a hotkey or button.
- The app captures the current screen.
- The user can ask a question.
- The model gives a useful answer.
- The app displays next steps.
- The app points to at least one screen location.
- The user can generate a reusable checklist or guide.
- The app has a clear safety posture.
```
