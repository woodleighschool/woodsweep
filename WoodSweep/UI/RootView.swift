import AppKit
import SwiftUI

struct RootView: View {
    let coordinator: ResetCoordinator

    @State private var restartError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            stateContent

            Divider()

            actions
        }
        .frame(width: 440, alignment: .leading)
        .padding(24)
        .background {
            WindowCloseGuard(
                allowsTermination: coordinator.allowsTermination
            )
        }
        .task {
            await coordinator.start()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if showsProgress {
                ProgressView()
                    .controlSize(.large)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 28))
                    .foregroundStyle(symbolStyle)
                    .frame(width: 32, height: 32)
            }

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch coordinator.state {
        case .checking, .backingUp, .resetting:
            EmptyView()
        case let .confirmation(username):
            Text(
                """
                Save your work before continuing. After the backup finishes, files in the \(username) account and settings for Word, Excel, and PowerPoint will be removed from this Mac. Unsaved changes may be lost.
                """
            )
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.secondary)
        case let .closingApps(statuses):
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "The following apps must close before the backup can begin."
                )
                .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    ForEach(statuses) { status in
                        OfficeApplicationRow(status: status)
                    }
                }
            }
        case let .failed(failure):
            Text(failure.message)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        case .restartRequired:
            Text(
                restartError
                    ?? "Restart this Mac before returning it to service."
            )
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            Spacer()

            switch coordinator.state {
            case .checking, .backingUp, .resetting:
                EmptyView()
            case .confirmation:
                Button("Cancel") {
                    quit()
                }
                Button("Back Up & Reset") {
                    Task {
                        await coordinator.confirmReset()
                    }
                }
                .keyboardShortcut(.defaultAction)
            case .closingApps:
                Button("Cancel") {
                    quit()
                }
                Button("Quit Apps") {
                    Task {
                        await coordinator.quitApps()
                    }
                }
                .keyboardShortcut(.defaultAction)
            case .failed:
                Button("Quit") {
                    quit()
                }
            case .restartRequired:
                Button("Later") {
                    quit()
                }
                Button("Restart") {
                    do {
                        restartError = nil
                        try coordinator.requestRestart()
                    } catch {
                        restartError = error.localizedDescription
                    }
                }
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
        case let .resetting(operation):
            "\(operationName(operation))…"
        case let .failed(failure):
            failureTitle(failure.operation)
        case .restartRequired:
            "Restart required"
        }
    }

    private var showsProgress: Bool {
        switch coordinator.state {
        case .checking, .backingUp, .resetting:
            true
        case .confirmation,
             .closingApps,
             .failed,
             .restartRequired:
            false
        }
    }

    private var symbolName: String {
        switch coordinator.state {
        case .failed:
            "exclamationmark.triangle"
        case .restartRequired:
            "arrow.clockwise.circle"
        case .confirmation, .closingApps:
            "laptopcomputer"
        case .checking, .backingUp, .resetting:
            preconditionFailure("Progress states do not render a symbol")
        }
    }

    private var symbolStyle: AnyShapeStyle {
        switch coordinator.state {
        case .failed:
            AnyShapeStyle(.orange)
        case .checking,
             .confirmation,
             .closingApps,
             .backingUp,
             .resetting,
             .restartRequired:
            AnyShapeStyle(.primary)
        }
    }

    private func operationName(_ operation: ResetOperation) -> String {
        switch operation {
        case .checkingConnection:
            "Checking backup connection"
        case .backingUp:
            "Backing up files"
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
        }
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
