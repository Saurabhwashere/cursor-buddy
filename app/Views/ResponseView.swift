import SwiftUI

struct ResponseView: View {
    let response: ScreenAnalysisResponse?
    let isLoading: Bool
    let onCopyChecklist: () -> Void
    let onExportChecklist: () -> Void

    var body: some View {
        Group {
            if isLoading {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView()
                    Text("Analyzing the current screen...")
                        .foregroundStyle(.secondary)
                }
            } else if let response {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section(title: "Answer", content: response.answer)

                        if !response.steps.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(response.steps.count == 1 ? "Next Step" : "Next Steps")
                                    .font(.headline)

                                ForEach(Array(response.steps.enumerated()), id: \.offset) { index, step in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(index + 1).")
                                            .foregroundStyle(.secondary)
                                        Text(step)
                                    }
                                }
                            }
                        }

                        if let checklist = response.checklist {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Text(checklist.title)
                                        .font(.headline)

                                    Spacer()

                                    Button("Copy") {
                                        onCopyChecklist()
                                    }

                                    Button("Export") {
                                        onExportChecklist()
                                    }
                                }

                                ForEach(Array(checklist.items.enumerated()), id: \.offset) { _, item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark.circle")
                                            .foregroundStyle(.green)
                                        Text(item)
                                    }
                                }
                            }
                        }

                        if !response.points.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Pointing At")
                                    .font(.headline)

                                ForEach(response.points) { point in
                                    Text(point.label)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !response.riskWarnings.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Warnings")
                                    .font(.headline)

                                ForEach(response.riskWarnings, id: \.self) { warning in
                                    Text(warning)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .textSelection(.enabled)
            } else {
                Text("Ask a question to get a screen-aware answer.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func section(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(content)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
