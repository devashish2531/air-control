// Features/Keyboard/KeyboardScreen.swift
// Keyboard tab (spec §4.1.6, §4.4). Per arch §3.2's MVVM pattern, this view constructs its
// `KeyboardViewModel` from the environment rather than requiring a special call from
// `RootTabView` (which just does `case .keyboard: KeyboardScreen()`): it reuses
// `environment.keyboard` when the integration/Connection agent has already assigned it a real
// `KeyboardBridge` (via `KeyboardFeature.makeBridge(sink:)`, see `Keyboard+Environment.swift`),
// falling back to a fresh no-op-backed bridge otherwise (previews, or before that wiring exists).
//
// iPad regular width (spec §4.1.10 motivates *pairing* touch input with the keyboard controls at
// this size class; the Touchpad feature's own drawer/side-panel structure — Keys/Macros/Presenter
// tabs nested inside the Touchpad screen — is that agent's file, not this one). This screen's own
// regular-width variant places a lightweight touchpad placeholder region next to the keyboard
// panel (per this agent's assignment) so the Keyboard tab itself isn't mostly empty space on iPad
// when reached directly from the root sidebar.

import SwiftUI
import UIKit
import AirMouseProtocol

public struct KeyboardScreen: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel: KeyboardViewModel?
    @FocusState private var isCommitFieldFocused: Bool
    /// Tracked purely so `keyboardPanel`'s `ScrollView` can add matching bottom inset (UI fix: the
    /// Media/Shortcuts rows were unreachable — hidden behind the software keyboard — once it was
    /// showing, since this screen's first responder is a raw `UIViewRepresentable`, not a SwiftUI
    /// `@FocusState` field, so SwiftUI's own automatic keyboard-avoidance inset doesn't apply).
    @State private var keyboardHeight: CGFloat = 0

    /// Default initializer used by `RootTabView` and SwiftUI previews; the view model is built
    /// lazily from `environment` on first appearance (see file header).
    public init() {}

    /// Explicit construction for `KeyboardFeature.make(environment:sink:)` and this module's own
    /// previews/tests that want a specific bridge/haptics pair up front.
    public init(bridge: KeyboardBridge, haptics: any HapticsService = UIKitHapticsService()) {
        _viewModel = State(initialValue: KeyboardViewModel(bridge: bridge, haptics: haptics))
    }

    public var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                Color.clear
            }
        }
        .task {
            guard viewModel == nil else { return }
            let bridge = (environment.keyboard as? KeyboardBridge) ?? KeyboardBridge()
            viewModel = KeyboardViewModel(bridge: bridge, haptics: environment.haptics)
        }
    }

    @ViewBuilder
    private func content(_ viewModel: KeyboardViewModel) -> some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    touchpadPlaceholder
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    keyboardPanel(viewModel)
                        .frame(width: 420)
                }
            } else {
                keyboardPanel(viewModel)
            }
        }
        .background {
            KeyInputHostRepresentable(bridge: viewModel.bridge)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                // On-device UI test hook only: stable identifier for the live-typing capture
                // host. No behaviour change; this view already becomes first responder
                // automatically whenever the Keyboard tab is visible (see
                // `KeyboardViewModel.onAppear()`), so tests don't rely on tapping it.
                .accessibilityIdentifier("keyboard.liveInput")
                .accessibilityHidden(true)
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .navigationTitle(Text("Keyboard", comment: "Root tab title"))
        .toolbar { toolbarContent(viewModel) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            keyboardHeight = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
    }

    /// Dismisses whichever keyboard is currently up (Live mode's hidden host view or Commit
    /// mode's visible text editor) without changing `mode` or any bridge/sink semantics.
    private func dismissKeyboard(_ viewModel: KeyboardViewModel) {
        isCommitFieldFocused = false
        viewModel.hideSystemKeyboard()
    }

    private var touchpadPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.quaternary.opacity(0.3))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "hand.point.up.left")
                        .font(.largeTitle)
                    Text("Touchpad", comment: "Keyboard tab iPad layout: touchpad placeholder region label")
                }
                .foregroundStyle(.secondary)
            }
            .padding()
            .accessibilityHidden(true)
    }

    private func keyboardPanel(_ viewModel: KeyboardViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                modeAndTrail(viewModel)
                if viewModel.mode == .commit {
                    commitEditor(viewModel)
                }
                ModifierBarView(viewModel: viewModel)
                ExtendedKeyBarView(viewModel: viewModel)
                MediaKeyBarView(viewModel: viewModel)
                ShortcutRowView(viewModel: viewModel)
                // Tapping the empty area below the last row dismisses the keyboard (UI fix), the
                // same way tapping outside a text field does elsewhere in the app.
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 60, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissKeyboard(viewModel) }
                    .accessibilityHidden(true)
            }
            .padding()
            .padding(.bottom, keyboardHeight)
        }
        .scrollDismissesKeyboard(.interactively)
        .airMouseDynamicTypeRange()
    }

    private func modeAndTrail(_ viewModel: KeyboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(selection: Binding(get: { viewModel.mode }, set: { viewModel.mode = $0 })) {
                Text("Live", comment: "Keyboard entry mode").tag(KeyboardInputMode.live)
                Text("Commit", comment: "Keyboard entry mode").tag(KeyboardInputMode.commit)
            } label: {
                Text("Input mode", comment: "Keyboard input mode segmented control accessibility label")
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(Text("Input mode", comment: "Keyboard input mode segmented control accessibility label"))

            if viewModel.mode == .live {
                Text(viewModel.isSecureEntry || viewModel.bridge.trailText.isEmpty ? " " : viewModel.bridge.trailText)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 20, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(ReduceMotion.isEnabled ? nil : .easeOut, value: viewModel.bridge.trailText)
                    // Typed content is never read aloud (spec §7 privacy / NFR-PRIV-004).
                    .accessibilityHidden(true)
            }
        }
    }

    private func commitEditor(_ viewModel: KeyboardViewModel) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: Binding(get: { viewModel.commitText }, set: { viewModel.commitText = $0 }))
                .frame(minHeight: 100, maxHeight: 200)
                .focused($isCommitFieldFocused)
                .textInputAutocapitalization(viewModel.isSecureEntry ? .never : .sentences)
                .autocorrectionDisabled(viewModel.isSecureEntry)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                .accessibilityLabel(Text("Commit mode text", comment: "Accessibility label for the commit-mode text editor"))
                // UI fix: Commit mode's text editor had no way to dismiss its keyboard either.
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            isCommitFieldFocused = false
                        } label: {
                            Text("Done", comment: "Keyboard screen: dismisses the commit-mode text editor's software keyboard")
                        }
                    }
                }
            Button {
                viewModel.sendCommit()
            } label: {
                Text("Send", comment: "Commit mode: send button")
            }
            .buttonStyle(.borderedProminent)
            .minimumTapTarget()
            .disabled(viewModel.commitText.isEmpty)
            .accessibilityHint(Text("Sends the typed text to the Mac", comment: "Accessibility hint for the commit-mode Send button"))
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(_ viewModel: KeyboardViewModel) -> some ToolbarContent {
        if viewModel.mode == .live {
            ToolbarItem(placement: .topBarLeading) {
                // UI fix: the software keyboard previously had no Done/hide affordance once shown
                // in Live mode (this hidden host view's first responder isn't SwiftUI-focus-based,
                // so the system never adds its own accessory chrome for it beyond `doneAccessory`
                // above the keyboard itself — this toolbar button covers hide *and* re-show).
                Button {
                    if viewModel.isSystemKeyboardVisible {
                        dismissKeyboard(viewModel)
                    } else {
                        viewModel.showSystemKeyboard()
                    }
                } label: {
                    Image(systemName: viewModel.isSystemKeyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                }
                .minimumTapTarget()
                .accessibleButton(
                    label: LocalizedStringKey(viewModel.isSystemKeyboardVisible ? "Hide keyboard" : "Show keyboard")
                )
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Toggle(isOn: Binding(get: { viewModel.isSecureEntry }, set: { viewModel.isSecureEntry = $0 })) {
                Image(systemName: viewModel.isSecureEntry ? "eye.slash.fill" : "eye.slash")
            }
            .toggleStyle(.button)
            .minimumTapTarget()
            .accessibleButton(
                label: LocalizedStringKey("Secure entry"),
                hint: LocalizedStringKey("Hides typed text and disables autocorrect")
            )
            .accessibleLatched(viewModel.isSecureEntry)

            if viewModel.mode == .commit {
                Toggle(isOn: Binding(get: { viewModel.returnSends }, set: { viewModel.returnSends = $0 })) {
                    Image(systemName: "return")
                }
                .toggleStyle(.button)
                .minimumTapTarget()
                .accessibleButton(label: LocalizedStringKey("Return sends"))
                .accessibleLatched(viewModel.returnSends)
            }

            Toggle(isOn: Binding(get: { viewModel.isPassthroughEnabled }, set: { viewModel.isPassthroughEnabled = $0 })) {
                Image(systemName: "keyboard")
            }
            .toggleStyle(.button)
            .minimumTapTarget()
            .accessibleButton(
                label: LocalizedStringKey("Hardware keyboard passthrough"),
                hint: LocalizedStringKey("Sends key presses from an attached hardware keyboard directly to the Mac")
            )
            .accessibleLatched(viewModel.isPassthroughEnabled)
        }
    }
}

#Preview {
    NavigationStack {
        KeyboardScreen()
    }
    .environment(\.appEnvironment, .preview())
}
