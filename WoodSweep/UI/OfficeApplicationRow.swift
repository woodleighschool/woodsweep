import AppKit
import SwiftUI

struct OfficeApplicationRow: View {
    let status: OfficeApplicationStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            Text(status.application.displayName)

            Spacer()

            if status.isWaitingForTermination {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(
                        "Waiting for \(status.application.displayName) to quit"
                    )
            } else {
                Text("Running")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var icon: NSImage {
        NSWorkspace.shared.icon(
            forFile: status.application.applicationURL.path
        )
    }
}
