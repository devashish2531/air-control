// Services/KeyboardBridge/KeyInputHostRepresentable.swift
// SwiftUI wrapper for `KeyInputHostView` (arch §3.2). The coordinator is the
// `KeyInputHostViewDelegate` and forwards every event straight to the injected `KeyboardBridge`,
// which owns all keyboard-domain state and every `KeyboardEventSink` call.
//
// docs/08 §3.2: the coordinator also owns the `UIHostingController` for the SwiftUI
// `KeyboardAccessoryBar` and hands `KeyInputHostView` only the resulting `UIView` via a closure —
// see that file's header for why. The bar's current tab is always `.keyboard` (this representable
// only ever backs the Keyboard screen's hidden host view); tab taps read `TabSwitcher` from the
// SwiftUI environment (docs/08 §2.2) and resign first responder afterwards.

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

        context.coordinator.configureAccessoryBar(for: uiView, tabSwitcher: context.environment.tabSwitcher)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
    }

    @MainActor
    public final class Coordinator: KeyInputHostViewDelegate {
        let bridge: KeyboardBridge
        private var hostingController: UIHostingController<KeyboardAccessoryBar>?

        init(bridge: KeyboardBridge) {
            self.bridge = bridge
        }

        /// Builds (once) and refreshes the `UIHostingController` behind the accessory bar's
        /// `UIInputView` (docs/08 §3.2). `KeyInputHostView` only ever sees the resulting `UIView`
        /// through `accessoryContentProvider`, never the hosting controller or SwiftUI itself.
        func configureAccessoryBar(for view: KeyInputHostView, tabSwitcher: TabSwitcher) {
            let bar = KeyboardAccessoryBar(
                currentTab: .keyboard,
                onSelectTab: { [weak view] tab in
                    tabSwitcher.switchTo(tab)
                    view?.requestHide()
                },
                onOpenSettings: { tabSwitcher.openSettings() },
                onDone: { [weak view] in view?.requestHide() }
            )
            if let hostingController {
                hostingController.rootView = bar
            } else {
                let controller = UIHostingController(rootView: bar)
                controller.view.backgroundColor = .clear
                hostingController = controller
                view.accessoryContentProvider = { [weak controller] in controller?.view }
            }
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
