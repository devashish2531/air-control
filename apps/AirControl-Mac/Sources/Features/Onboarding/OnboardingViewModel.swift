// spec §5.2 "Permission onboarding (Accessibility only)". Four steps, re-enterable from Settings ›
// General › "Run setup again"; completion flag in UserDefaults (`am.helper.setupCompleted`, arch §6.2).
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
public final class OnboardingViewModel {
    public enum Step: Int, CaseIterable, Sendable {
        case accessibility
        case launchAtLogin
        case firewall
        case pair
    }

    public let permissions: PermissionsService
    public let settings: HostSettings

    public private(set) var currentStepIndex = 0
    public var launchAtLoginEnabled: Bool
    public private(set) var launchAtLoginRequiresApproval = false
    public private(set) var firewallEnabled: Bool

    public init(permissions: PermissionsService, settings: HostSettings) {
        self.permissions = permissions
        self.settings = settings
        launchAtLoginEnabled = settings.launchAtLogin
        firewallEnabled = Self.isSystemFirewallEnabled()
    }

    /// Step 3 "Firewall" is shown only if the system firewall is on (spec §5.2 step 3).
    public var steps: [Step] {
        firewallEnabled ? Step.allCases : Step.allCases.filter { $0 != .firewall }
    }

    public var currentStep: Step { steps[min(currentStepIndex, steps.count - 1)] }
    public var isLastStep: Bool { currentStepIndex >= steps.count - 1 }

    public func goToNextStep() {
        guard !isLastStep else { return }
        currentStepIndex += 1
    }

    public func goToPreviousStep() {
        guard currentStepIndex > 0 else { return }
        currentStepIndex -= 1
    }

    /// Called by the polling loop; auto-advances step 1 with a checkmark once granted (spec §5.2).
    public func accessibilityStatusChanged() {
        if permissions.isAccessibilityTrusted, currentStep == .accessibility {
            goToNextStep()
        }
    }

    /// Step 2 "Launch at login" checkbox default on (spec §5.2 step 2).
    public func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginEnabled = enabled
        settings.launchAtLogin = enabled
        guard enabled else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            Log.ui.error("SMAppService.register failed: \(String(describing: error), privacy: .public)")
        }
        launchAtLoginRequiresApproval = SMAppService.mainApp.status == .requiresApproval
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    public func markCompleted() {
        settings.setupCompleted = true
    }

    /// spec §5.2 step 3 gate: `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`.
    static func isSystemFirewallEnabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/ApplicationFirewall/socketfilterfw")
        process.arguments = ["--getglobalstate"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.localizedCaseInsensitiveContains("enabled")
        } catch {
            return false
        }
    }
}
