// PairingWindow — spec §5.1.3 "Pairing / QR" window, §3.1.3 (QR payload / error correction),
// §3.1.4 (60 s secret rotation). Replaces the networking-agent placeholder noted in this file's
// previous revision. Owned by the networking agent (assignment: "Features/Pairing/").
//
// Talks to the shell's `HostServing` (`App/ServiceProtocols.swift`) only — `openPairingWindow()`
// returns the QR/manual-fallback URL string; this view owns the countdown/regeneration polling and
// QR rendering. Where the concrete service is this module's own `HostServer` (checked via a
// best-effort downcast, never required), it also reads `PairingService.Status` for the richer
// "Waiting… / Paired with <device> / locked out" copy spec §5.1.3 asks for; against any other
// `HostServing` (e.g. a placeholder, in a preview or before the integration agent wires the real
// type in) it falls back to a plain "Waiting…"/"Paired" derived from whether a URL was returned.
import AirMouseCore
import CoreImage.CIFilterBuiltins
import SwiftUI

struct PairingWindow: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var pairingURLString: String?
    @State private var qrImage: NSImage?
    @State private var secondsRemaining: Int = PairingWindow.secretLifetimeSeconds
    @State private var showURL = false
    @State private var statusPhase: StatusPhase = .waiting
    @State private var pairedDeviceName: String?
    @State private var optionHeldAtPairing = false
    @State private var pollTask: Task<Void, Never>?

    static let secretLifetimeSeconds = 60

    private enum StatusPhase: Equatable {
        case waiting
        case deviceConnecting
        case paired
        case lockedOut
        case unavailable
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(environment.settings.deviceDisplayName)
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .frame(width: 320, height: 320)
                if let qrImage {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 300, height: 300)
                } else {
                    ProgressView()
                }
                countdownRing
                    .frame(width: 340, height: 340)
            }

            statusView

            DisclosureGroup("Can't scan?", isExpanded: $showURL) {
                if let pairingURLString {
                    Text(pairingURLString)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: 340)

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 420, height: 520)
        .background(Color.white)
        .onAppear { start() }
        .onDisappear { stop() }
    }

    @ViewBuilder
    private var countdownRing: some View {
        if statusPhase == .waiting || statusPhase == .deviceConnecting {
            Circle()
                .trim(from: 0, to: CGFloat(secondsRemaining) / CGFloat(Self.secretLifetimeSeconds))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: secondsRemaining)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch statusPhase {
        case .waiting:
            Text("Waiting…").foregroundStyle(.secondary)
        case .deviceConnecting:
            Text("Device connecting…").foregroundStyle(.secondary)
        case .paired:
            Label("Paired with \(pairedDeviceName ?? "device")", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .lockedOut:
            Label("Too many failed attempts — try again", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .unavailable:
            Text("Pairing unavailable").foregroundStyle(.secondary)
        }
    }

    // MARK: - Lifecycle

    private func start() {
        guard pollTask == nil else { return }
        pollTask = Task {
            await openWindow()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await tick()
            }
        }
    }

    private func stop() {
        pollTask?.cancel()
        pollTask = nil
        Task { await environment.hostService.closePairingWindow() }
    }

    private func openWindow() async {
        guard let urlString = try? await environment.hostService.openPairingWindow() else {
            statusPhase = .unavailable
            return
        }
        pairingURLString = urlString
        qrImage = Self.renderQRCode(for: urlString)
        secondsRemaining = Self.secretLifetimeSeconds
        if statusPhase != .paired {
            statusPhase = .waiting
        }
    }

    private func tick() async {
        if let hostServer = environment.hostService as? HostServer {
            let status = await hostServer.pairingServiceStatusForUI()
            switch status {
            case .waiting:
                statusPhase = .waiting
            case .deviceConnecting:
                statusPhase = .deviceConnecting
            case .paired(let deviceName):
                if statusPhase != .paired {
                    optionHeldAtPairing = NSEvent.modifierFlags.contains(.option)
                    pairedDeviceName = deviceName
                    statusPhase = .paired
                    // spec §5.1.3: "Paired with <device>" (green, 2 s, then window closes unless ⌥ is held).
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        if !optionHeldAtPairing {
                            dismiss()
                        }
                    }
                }
                return
            case .lockedOut:
                statusPhase = .lockedOut
                return
            case .closed:
                break
            }
        }

        guard statusPhase != .paired, statusPhase != .lockedOut else { return }
        secondsRemaining -= 1
        if secondsRemaining <= 0 {
            await openWindow()
        }
    }

    // MARK: - QR rendering (spec §3.1.3: error correction level M, white background, ≥ 300 pt)

    private static func renderQRCode(for string: String) -> NSImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }

        // Scale the (small, 1 pt/module) generated image up to a crisp ≥ 300 pt bitmap with a
        // 4-module quiet zone, rendered on white regardless of appearance (spec §3.1.3).
        let quietZone: CGFloat = 4
        let bordered = outputImage.transformed(by: CGAffineTransform(
            translationX: quietZone,
            y: quietZone
        )).cropped(to: CGRect(
            x: 0, y: 0,
            width: outputImage.extent.width + quietZone * 2,
            height: outputImage.extent.height + quietZone * 2
        ))
        let targetSize: CGFloat = 300
        let scale = targetSize / bordered.extent.width
        let scaled = bordered.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: targetSize, height: targetSize))
    }
}
