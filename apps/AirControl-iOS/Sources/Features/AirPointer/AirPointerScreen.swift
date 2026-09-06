// Features/AirPointer/AirPointerScreen.swift
// Air Pointer (gyro) tab, spec §4.1.5. Replaces the placeholder. Portrait: status card (top third),
// click area + scroll strip (middle), clutch button (bottom). Landscape moves the clutch to the
// trailing edge (spec §4.1.5). iPad: same layout, wider, centered with a max content width so
// controls don't stretch to an uncomfortable span.
//
// Per this assignment's note on the `AirControlProtocol.Text` / `SwiftUI.Text` name collision: this
// file does not import `AirControlProtocol` and every text literal is written `SwiftUI.Text(...)`.
import SwiftUI

public struct AirPointerScreen: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var ownedViewModel: AirPointerViewModel?
    private let injectedViewModel: AirPointerViewModel?

    /// Used by `RootTabView` (`AirPointerScreen()`), which constructs this with no dependencies —
    /// the view model is built from the environment on first appearance.
    public init() {
        self.injectedViewModel = nil
    }

    /// Used by `AirPointerFeature.make(environment:)` / previews / tests, where the caller already
    /// has (or wants to control) the view model.
    public init(viewModel: AirPointerViewModel) {
        self.injectedViewModel = viewModel
    }

    private var viewModel: AirPointerViewModel? { injectedViewModel ?? ownedViewModel }

    public var body: some View {
        Group {
            if let viewModel {
                AirPointerContentView(
                    viewModel: viewModel,
                    connectionState: environment.connection.connectionState,
                    isLeftHanded: environment.userSettings.snapshot.appearance.handedness == .left,
                    isCompactHeight: verticalSizeClass == .compact,
                    isRegularWidth: horizontalSizeClass == .regular
                )
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard injectedViewModel == nil, ownedViewModel == nil else { return }
            ownedViewModel = AirPointerFeature.makeViewModel(environment: environment)
        }
    }
}

/// The actual tab content, once a view model exists. Split out so previews/tests can construct it
/// directly with a synthetic view model without going through `AppEnvironment`.
struct AirPointerContentView: View {
    let viewModel: AirPointerViewModel
    let connectionState: ConnectionState
    let isLeftHanded: Bool
    let isCompactHeight: Bool
    let isRegularWidth: Bool

    var body: some View {
        Group {
            if viewModel.engine.isGyroAvailable {
                available
            } else {
                AirPointerUnsupportedView()
            }
        }
        .background(ShakeDetectingView(onShake: viewModel.shakeDetected))
        .task { await viewModel.onAppear() }
        .onDisappear { Task { await viewModel.onDisappear() } }
    }

    @ViewBuilder
    private var available: some View {
        if isCompactHeight {
            landscapeLayout
        } else {
            portraitLayout
        }
    }

    private var portraitLayout: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let banner = connectionBanner {
                    banner
                }
                AirPointerStatusCard(
                    engineState: viewModel.engine.state,
                    calibrationProgress: viewModel.engine.calibrationProgress,
                    isRawFallbackIndicatorVisible: viewModel.engine.isRawFallbackIndicatorVisible,
                    isFirstUse: !viewModel.hasCompletedGyroTutorial
                )
                HStack(spacing: 10) {
                    AirPointerClickArea(viewModel: viewModel, isLeftHanded: isLeftHanded)
                    AirPointerScrollStrip(viewModel: viewModel)
                }
                .frame(minHeight: 160)
                HStack {
                    if isLeftHanded { Spacer(minLength: 0) }
                    AirPointerClutchButton(viewModel: viewModel, engineState: viewModel.engine.state)
                    if !isLeftHanded { Spacer(minLength: 0) }
                }
                AirPointerSettingsPanel(viewModel: viewModel)
            }
            .padding()
            .frame(maxWidth: isRegularWidth ? 640 : .infinity)
            .frame(maxWidth: .infinity)
        }
    }

    /// spec §4.1.5: "Landscape moves the clutch to the trailing edge."
    private var landscapeLayout: some View {
        HStack(spacing: 16) {
            ScrollView {
                VStack(spacing: 12) {
                    if let banner = connectionBanner {
                        banner
                    }
                    AirPointerStatusCard(
                        engineState: viewModel.engine.state,
                        calibrationProgress: viewModel.engine.calibrationProgress,
                        isRawFallbackIndicatorVisible: viewModel.engine.isRawFallbackIndicatorVisible,
                        isFirstUse: !viewModel.hasCompletedGyroTutorial
                    )
                    HStack(spacing: 10) {
                        AirPointerClickArea(viewModel: viewModel, isLeftHanded: isLeftHanded)
                        AirPointerScrollStrip(viewModel: viewModel)
                    }
                    AirPointerSettingsPanel(viewModel: viewModel)
                }
                .padding()
            }
            AirPointerClutchButton(viewModel: viewModel, engineState: viewModel.engine.state)
                .padding(.trailing)
        }
    }

    private var connectionBanner: AirPointerConnectionBanner? {
        if case .connected = connectionState { return nil }
        return AirPointerConnectionBanner(connectionState: connectionState)
    }
}

#Preview("Available") {
    NavigationStack {
        AirPointerContentView(
            viewModel: .preview(),
            connectionState: .connected(hostName: "Dev's Mac"),
            isLeftHanded: false,
            isCompactHeight: false,
            isRegularWidth: false
        )
    }
}

#Preview("Not connected") {
    NavigationStack {
        AirPointerContentView(
            viewModel: .preview(),
            connectionState: .idle,
            isLeftHanded: false,
            isCompactHeight: false,
            isRegularWidth: false
        )
    }
}

#Preview("Unsupported device") {
    AirPointerUnsupportedView()
}
