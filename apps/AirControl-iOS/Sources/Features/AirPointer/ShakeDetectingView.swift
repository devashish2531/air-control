// Features/AirPointer/ShakeDetectingView.swift
// spec §4.1.5 / §4.3.6: "Shake → recenter when enabled... `UIEvent.subtype == .motionShake`."
// SwiftUI has no shake gesture, so this wraps a `UIViewController` that becomes first responder
// and overrides `motionEnded`, matching the exact API the spec names.
import SwiftUI
import UIKit

struct ShakeDetectingView: UIViewControllerRepresentable {
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> ShakeDetectingViewController {
        let controller = ShakeDetectingViewController()
        controller.onShake = onShake
        return controller
    }

    func updateUIViewController(_ controller: ShakeDetectingViewController, context: Context) {
        controller.onShake = onShake
    }
}

final class ShakeDetectingViewController: UIViewController {
    var onShake: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        onShake?()
    }
}
