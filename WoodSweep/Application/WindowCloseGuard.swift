import AppKit
import SwiftUI

struct WindowCloseGuard: NSViewRepresentable {
    let allowsTermination: Bool

    func makeNSView(context _: Context) -> CloseGuardView {
        CloseGuardView()
    }

    func updateNSView(
        _ nsView: CloseGuardView,
        context _: Context
    ) {
        nsView.allowsTermination = allowsTermination
    }
}

final class CloseGuardView: NSView {
    var allowsTermination = true {
        didSet {
            updateCloseButton()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateCloseButton()
    }

    private func updateCloseButton() {
        window?.standardWindowButton(.closeButton)?.isEnabled =
            allowsTermination
    }
}
