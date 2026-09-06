// Features/Onboarding/OnboardingScreen.swift
// First-run flow. Presented as a full-screen cover (spec §4.1: "Onboarding … presented as
// full-screen covers").
//
// DEVIATION from spec §4.1.1's literal 3-page order (welcome → install helper → local network):
// this agent's assignment explicitly asks for welcome → local-network explanation → camera
// explanation → install helper → hand-off to pairing. Kept as specified in the assignment;
// flagged here and in the final report since it does not match §4.1.1 verbatim. The English
// copy for the pages spec *does* define (welcome, install helper, local network) is reproduced
// exactly; the camera page's copy is original since spec doesn't give onboarding copy for it
// (camera permission copy in spec only appears at Scan QR denial, E-CAMERA, spec §9).

import SwiftUI
import Observation

public struct OnboardingScreen: View {
    @Environment(\.appEnvironment) private var environment
    @State private var model: OnboardingModel?
    let onFinished: () -> Void

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        Group {
            if let model {
                OnboardingContent(model: model, environment: environment, onFinished: onFinished)
            } else {
                Color.clear
            }
        }
        .task {
            if model == nil {
                model = OnboardingModel(userSettings: environment.userSettings)
            }
        }
    }
}

private struct OnboardingContent: View {
    @Bindable var model: OnboardingModel
    let environment: AppEnvironment
    let onFinished: () -> Void

    @State private var isPresentingPairing = false

    var body: some View {
        TabView(selection: $model.currentPage) {
            WelcomePage(onContinue: model.advance, onSkip: skip)
                .tag(OnboardingPage.welcome)
            LocalNetworkPage(onContinue: { model.continueFromLocalNetwork(connection: environment.connection) }, onSkip: skip)
                .tag(OnboardingPage.localNetwork)
            CameraPermissionPage(model: model, onSkip: skip)
                .tag(OnboardingPage.camera)
            InstallHelperPage(onFinished: {
                model.finish()
                isPresentingPairing = true
            })
                .tag(OnboardingPage.installHelper)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .fullScreenCover(isPresented: $isPresentingPairing, onDismiss: onFinished) {
            NavigationStack { PairingScreen() }
        }
        .airMouseDynamicTypeRange()
    }

    private func skip() {
        model.skip()
        onFinished()
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingPageLayout(
            systemImage: "iphone.gen3.radiowaves.left.and.right",
            title: Text("Your iPhone is now a trackpad, air mouse and keyboard for your Mac.", comment: "Onboarding page 1 (spec §4.1.1)"),
            message: nil,
            primaryTitle: Text("Continue", comment: "Onboarding primary action"),
            onPrimary: onContinue,
            secondaryTitle: Text("Skip", comment: "Onboarding: skips the remaining first-run pages"),
            onSecondary: onSkip
        )
    }
}

// MARK: - Page 2: Local network

private struct LocalNetworkPage: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingPageLayout(
            systemImage: "wifi",
            title: Text("Find your Mac on Wi-Fi", comment: "Onboarding local network page title"),
            message: Text("Air Mouse needs to see devices on your Wi-Fi to find your Mac. iOS will ask you next. Nothing leaves your network.", comment: "Onboarding page 3 (spec §4.1.1)"),
            primaryTitle: Text("Continue", comment: "Onboarding primary action"),
            onPrimary: onContinue,
            secondaryTitle: Text("Skip", comment: "Onboarding: skips the remaining first-run pages"),
            onSecondary: onSkip
        )
    }
}

// MARK: - Page 3: Camera (assignment addition; see deviation note above)

private struct CameraPermissionPage: View {
    let model: OnboardingModel
    let onSkip: () -> Void

    var body: some View {
        OnboardingPageLayout(
            systemImage: "camera.viewfinder",
            title: Text("Scan your Mac's pairing code", comment: "Onboarding camera page title"),
            message: Text("Air Mouse uses the camera only to scan the QR code your Mac shows during pairing. Nothing is recorded or stored.", comment: "Onboarding camera page body"),
            primaryTitle: Text("Continue", comment: "Onboarding primary action"),
            onPrimary: { Task { await model.requestCameraPermission() } },
            isPrimaryInProgress: model.isRequestingCameraPermission,
            secondaryTitle: Text("Skip", comment: "Onboarding: skips the remaining first-run pages"),
            onSecondary: onSkip
        )
    }
}

// MARK: - Page 4: Install helper

private struct InstallHelperPage: View {
    let onFinished: () -> Void
    private let brewCommand = "brew install --cask air-mouse"
    private let releasesURLString = "https://github.com/air-mouse/air-mouse/releases/latest"

    // docs/08 §4: page content scrolls above a single bottom button stack — see
    // `OnboardingPageLayout` below for the shared pattern; this page has bespoke content (the
    // install instructions) so it lays out the same way by hand instead of going through that type.
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Install the Mac helper", comment: "Onboarding page 2 title (spec §4.1.1)")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let releasesURL = URL(string: releasesURLString) {
                    Link(destination: releasesURL) {
                        Label {
                            Text("Open GitHub Releases", comment: "Onboarding: link to the GitHub Releases page")
                        } icon: {
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                    .minimumTapTarget()
                }
                HStack {
                    Text(brewCommand)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityLabel(Text("Terminal command: \(brewCommand)", comment: "Accessibility label for the brew install command"))
                    Spacer()
                    Button {
                        UIPasteboard.general.string = brewCommand
                    } label: {
                        Text("Copy", comment: "Onboarding: copies the brew install command")
                    }
                    .minimumTapTarget()
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: onFinished) {
                    Text("I've installed it", comment: "Onboarding page 2 primary action (spec §4.1.1)")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.bar)
        }
    }
}

// MARK: - Shared page layout

/// docs/08 §4: "buttons must never overlap … single bottom `VStack(spacing: 12)` inside
/// `safeAreaInset(edge: .bottom)` with a `.borderedProminent` primary and `.bordered` secondary,
/// both `frame(maxWidth: .infinity)`, 50 pt tall; page content in a `ScrollView` above." Applies
/// on iPhone SE (3rd gen) and iPhone 17 Pro alike since the content scrolls instead of being
/// squeezed between fixed spacers — no forced `.dark`, follows the device/app theme.
private struct OnboardingPageLayout: View {
    let systemImage: String
    let title: Text
    /// Optional body copy under the title. Named `message` (not `body`) to avoid colliding with
    /// `View.body`.
    let message: Text?
    let primaryTitle: Text
    let onPrimary: () -> Void
    var isPrimaryInProgress: Bool = false
    var secondaryTitle: Text? = nil
    var onSecondary: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: systemImage)
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                title
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let message {
                    message
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: onPrimary) {
                    Group {
                        if isPrimaryInProgress {
                            ProgressView()
                        } else {
                            primaryTitle
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPrimaryInProgress)

                if let secondaryTitle, let onSecondary {
                    Button(action: onSecondary) {
                        secondaryTitle
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPrimaryInProgress)
                }
            }
            .padding()
            .background(.bar)
        }
    }
}

#Preview {
    OnboardingScreen(onFinished: {})
        .environment(\.appEnvironment, .preview())
}
