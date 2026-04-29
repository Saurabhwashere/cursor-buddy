import SwiftUI

struct ArtifactPreviewView: View {
    let artifact: GeneratedArtifact
    let onCopy: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reusable Guide")
                        .font(.headline)

                    Text(artifact.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Copy") {
                    onCopy()
                }

                Button("Save") {
                    onSave()
                }

                Button("Close") {
                    onClose()
                }
            }

            ScrollView {
                Text(artifact.markdown)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 180, maxHeight: 260)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
