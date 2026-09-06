// Services/KeyboardBridge/KeyInputHostRepresentable.swift
// SwiftUI wrapper for `KeyInputHostView` (arch §3.2). The coordinator is the
// `KeyInputHostViewDelegate` and forwards every event straight to the injected `KeyboardBridge`,
// which owns all keyboard-domain state and every `KeyboardEventSink` call.

import SwiftUI

public struct KeyInputHostRepresentable: UIViewRepresentable {
    let bridge: KeyboardBridge

    public init(bridge: KeyboardBridge) {
        self.bridge = bridge
    }

    public func makeUIView(context: Context) -> KeyInputHostView {
        let view = KeyInputHostView()
        view.hostDelegate = context.coordinator
        bridge.attach(hostView: view)
        return view
    }

    public func updateUIView(_ uiView: KeyInputHostView, context: Context) {
        uiView.isHardwarePassthroughEnabled = bridge.isPassthroughEnabled

        switch (bridge.mode, bridge.isSecureEntry) {
        case (.live, true):
            uiView.configureForSecureEntry()
        case (.live, false):
            uiView.configureForLiveMode()
        case (.commit, _):
            uiView.configureForCommitMode()
        }

        if bridge.wantsFirstResponder, uiView.window != nil, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !bridge.wantsFirstResponder, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
    }

    @MainActor
    public final class Coordinator: KeyInputHostViewDelegate {
        let bridge: KeyboardBridge

        init(bridge: KeyboardBridge) {
            self.bridge = bridge
        }

        public func keyInputHost(_ view: KeyInputHostView, didInsertText text: String) {
            bridge.handleLiveInsertedText(text, resetting: view)
        }

        public func keyInputHostDidDeleteBackward(_ view: KeyInputHostView) {
            bridge.handleLiveDeleteBackward(resetting: view)
        }

        public func keyInputHost(_ view: KeyInputHostView, hardwareKeyEvent event: HardwareKeyEvent) {
            bridge.handleHardwareKeyEvent(event)
        }

        public func keyInputHostDidRequestHide(_ view: KeyInputHostView) {
            bridge.wantsFirstResponder = false
        }
    }
}
