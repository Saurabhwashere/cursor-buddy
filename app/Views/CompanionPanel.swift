import SwiftUI

struct CompanionPanel: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Ask Codex")
                        .font(.headline)

                    Spacer()

                    Text("Option")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }

                Picker("Mode", selection: $appState.selectedMode) {
                    ForEach(GuidanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(appState.isLoading)

                Text(appState.summonHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("How do I log in? What do I click next?", text: $appState.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .lineLimit(2...4)
                    .padding(12)
                    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    .focused($isPromptFocused)
                    .disabled(appState.isLoading)
                    .onSubmit {
                        Task {
                            await appState.captureAndAnalyze()
                        }
                    }
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await appState.captureAndAnalyze()
                    }
                } label: {
                    if appState.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Looking...")
                        }
                    } else {
                        Text("Ask About This Screen")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(appState.isLoading)

                Button("I did that") {
                    appState.setDefaultNextQuestion()
                    isPromptFocused = true
                }
                .disabled(appState.isLoading)
            }

            HStack(spacing: 12) {
                Button("Hide Pointer") {
                    appState.hidePointerOverlay()
                }
                .disabled(!appState.isPointerOverlayVisible)

                Button("Show Pointer Again") {
                    appState.showPointerOverlayAgain()
                }
                .disabled(!appState.canShowPointerOverlay || appState.isPointerOverlayVisible)

                Button("Create Guide") {
                    appState.createReusableGuide()
                }
                .disabled(appState.latestResponse == nil || appState.isLoading)

                Spacer()

                if let screenshot = appState.latestScreenshot {
                    Text("\(screenshot.width)x\(screenshot.height) captured")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            if let errorMessage = appState.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Divider()

            if let artifact = appState.pendingArtifact {
                ArtifactPreviewView(
                    artifact: artifact,
                    onCopy: appState.copyPendingArtifact,
                    onSave: appState.savePendingArtifact,
                    onClose: appState.closePendingArtifact
                )

                Divider()
            }

            ResponseView(
                response: appState.latestResponse,
                isLoading: appState.isLoading,
                onCopyChecklist: appState.copyChecklistToClipboard,
                onExportChecklist: appState.exportChecklistToMarkdown
            )

            Spacer(minLength: 0)
        }
        .padding(22)
        .onAppear {
            appState.startHotkeyMonitoring()
            isPromptFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Codex Cursor")
                .font(.largeTitle.bold())

            Text("Press Option anywhere. Ask one question. Get the next step.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
