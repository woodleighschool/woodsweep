import AppKit
import SwiftUI

struct RootView: View {
    let coordinator: ResetCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbolName)
                    .font(.system(size: 28))
                    .foregroundStyle(symbolStyle)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(minHeight: 32)

                    detail
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 16)

            actions
        }
        .frame(width: 440)
        .frame(minHeight: 184, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        .windowDismissBehavior(
            coordinator.allowsTermination ? .enabled : .disabled
        )
        .task {
            await coordinator.start()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch coordinator.state {
        case .checking, .backingUp, .resetting:
            ProgressView()
                .progressViewStyle(.linear)

            if let activity {
                Text(activity)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case let .confirmation(username):
            Text(
                """
                Save your work before continuing. After the backup finishes, files in the \(username) account and settings for Word, Excel, and PowerPoint will be removed from this Mac, and it will restart. Unsaved changes may be lost.
                """
            )
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.secondary)
        case let .closingApps(statuses):
            Text(
                "The following apps must close before the backup can begin."
            )
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(statuses) { status in
                    OfficeApplicationRow(status: status)
                }
            }
        case .restarting:
            Text(
                "This Mac is restarting. If it doesn’t, choose Restart from the Apple menu."
            )
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.secondary)
        case let .failed(failure):
            if failure.operation == .restarting {
                Text(
                    "The reset finished. Choose Restart from the Apple menu."
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            FailureMessage(message: failure.message)
        }
    }

    private var actions: some View {
        HStack {
            Spacer()

            switch coordinator.state {
            case .backingUp, .resetting, .restarting:
                EmptyView()
            case .checking:
                Button("Cancel", action: quit)
                    .keyboardShortcut(.cancelAction)
            case .confirmation:
                Button("Cancel", action: quit)
                    .keyboardShortcut(.cancelAction)
                Button("Back Up & Reset") {
                    Task {
                        await coordinator.confirmReset()
                    }
                }
                .keyboardShortcut(.defaultAction)
            case .closingApps:
                Button("Cancel", action: quit)
                    .keyboardShortcut(.cancelAction)
                Button("Quit Apps") {
                    Task {
                        await coordinator.quitApps()
                    }
                }
                .keyboardShortcut(.defaultAction)
            case .failed:
                Button("Quit", action: quit)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var title: String {
        switch coordinator.state {
        case .checking:
            "Checking backup connection…"
        case .confirmation:
            "Prepare this Mac"
        case .closingApps:
            "Close apps to continue"
        case .backingUp:
            "Backing up files…"
        case .resetting:
            "Resetting this Mac…"
        case .restarting:
            "Reset complete"
        case let .failed(failure):
            failureTitle(failure.operation)
        }
    }

    private var activity: String? {
        guard case let .resetting(operation) = coordinator.state else {
            return nil
        }
        return switch operation {
        case .resettingWord:
            "Resetting Word"
        case .resettingExcel:
            "Resetting Excel"
        case .resettingPowerPoint:
            "Resetting PowerPoint"
        case let .clearing(directory):
            "Clearing \(directory)"
        case let .removing(item):
            "Removing \(item)"
        case .checkingConnection, .backingUp, .restarting:
            nil
        }
    }

    private var symbolName: String {
        switch coordinator.state {
        case .failed:
            "exclamationmark.triangle"
        case .restarting:
            "checkmark.circle"
        case .checking,
             .confirmation,
             .closingApps,
             .backingUp,
             .resetting:
            "laptopcomputer"
        }
    }

    private var symbolStyle: AnyShapeStyle {
        switch coordinator.state {
        case .failed:
            AnyShapeStyle(.orange)
        case .restarting:
            AnyShapeStyle(.green)
        case .checking,
             .confirmation,
             .closingApps,
             .backingUp,
             .resetting:
            AnyShapeStyle(.primary)
        }
    }

    private func failureTitle(_ operation: ResetOperation) -> String {
        switch operation {
        case .checkingConnection:
            "Backup unavailable"
        case .backingUp:
            "Backup failed"
        case .resettingWord:
            "Word reset failed"
        case .resettingExcel:
            "Excel reset failed"
        case .resettingPowerPoint:
            "PowerPoint reset failed"
        case let .clearing(directory):
            "Clearing \(directory) failed"
        case let .removing(item):
            "Removing \(item) failed"
        case .restarting:
            "Restart failed"
        }
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

/// Shows an error of any length without letting it size the window.
private struct FailureMessage: View {
    let message: String

    var body: some View {
        ViewThatFits(in: .vertical) {
            text

            ScrollView {
                text
            }
        }
        .frame(maxHeight: 220, alignment: .top)
    }

    private var text: some View {
        Text(message)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
