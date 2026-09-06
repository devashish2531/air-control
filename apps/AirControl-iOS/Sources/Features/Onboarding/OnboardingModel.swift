// Features/Onboarding/OnboardingModel.swift
// Backing model for the first-run flow. Spec §4.1.1 describes a 3-page `TabView(.page)`
// (welcome → install helper → local network, the last of which triggers the first `NWBrowser`
// and pushes Scan QR); this agent's assignment additionally asks for an explicit camera
// permission explanation step and a specific ordering (welcome → local network → camera →
// install helper → hand off to pairing) — see the deviation note in `OnboardingScreen.swift`.
//
// "Skip" exists on every page (spec §4.1.1) and completion is stored in
// `UserDefaults.onboardingCompleted` via `UserSettings.onboardingCompleted` (arch §6.2).

import Foundation
import AVFoundation
import Observation

public enum OnboardingPage: Int, CaseIterable, Sendable {
    case welcome
    case localNetwork
    case camera
    case installHelper
}

@MainActor
@Observable
public final class OnboardingModel {
    public var currentPage: OnboardingPage = .welcome
    public var isRequestingCameraPermission = false
    public var cameraPermissionDenied = false

    private let userSettings: UserSettings

    public init(userSettings: UserSettings) {
        self.userSettings = userSettings
    }

    public func advance() {
        guard let next = OnboardingPage(rawValue: currentPage.rawValue + 1) else { return }
        currentPage = next
    }

    /// Local network page's "Continue" (spec §4.1.1 page 3): "triggers the first `NWBrowser`
    /// (system prompt)". The actual `NWBrowser` lives in the Connection agent's actor, out of
    /// scope for this module; `ConnectionManaging`'s minimal protocol only exposes
    /// `connect()/disconnect()` to a specific host, not "start browsing". Calling `connect()`
    /// here is a best-effort placeholder so the local-network permission prompt still fires via
    /// whatever Bonjour/Network code that method ends up touching — the Connection agent should
    /// confirm this is sufficient or add a dedicated "start browsing" entry point.
    public func continueFromLocalNetwork(connection: any ConnectionManaging) {
        Task { await connection.connect() }
        advance()
    }

    public func requestCameraPermission() async {
        isRequestingCameraPermission = true
        defer { isRequestingCameraPermission = false }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraPermissionDenied = !granted
        advance()
    }

    public func finish() {
        userSettings.onboardingCompleted = true
    }

    public func skip() {
        finish()
    }
}
