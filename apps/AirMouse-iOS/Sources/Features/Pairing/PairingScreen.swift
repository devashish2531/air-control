// Features/Pairing/PairingScreen.swift
// Scan QR (spec §4.1.2): `DataScannerViewController` when supported (VisionKit, iOS 16+ hardware
// with a Neural Engine), else `AVCaptureMetadataOutput`; camera-permission explanation with a
// Settings deep link; paste-pairing-link fallback (spec §3.1.3: "the manual fallback is the full
// URL as copyable text"); connecting/verifying/paired/failed states per spec §9; haptics; auto-
// dismiss to the caller on success.
//
// Drives the real connection flow by downcasting `environment.connection as? ConnectionManager`
// (this agent's own concrete type — see `ConnectionManager+Environment.swift`'s header comment for
// why a downcast, not a widened shell protocol, is the wiring seam here) — falls back to a
// disabled "not connected" state if a `ConnectionManager` isn't installed yet (previews, or before
// app-launch DI wiring runs).
//
// docs/08 §4 audit note: this screen's `Color.black` backdrop and fixed `.white`/`.black` chrome
// (close/torch buttons, camera-denied copy, the collapsed "Paste pairing link" pill) are the one
// deliberate exception to "replace black/white with semantic colours" — it's a camera-viewfinder
// screen (like a QR scanner or Camera app), always dark chrome over a live/absent video feed,
// independent of the app's own Appearance setting. Every part of this screen that *isn't* fixed
// viewfinder chrome already uses adaptive styles (`progressOverlay`'s `.regularMaterial` card with
// `.primary`/`.secondary`/`.green`/`.red`), so it renders correctly in both Light and Dark —
// verified in the simulator with both `-AppleInterfaceStyle` values.

import AVFoundation
import SwiftUI
import UIKit
import VisionKit

public struct PairingScreen: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var cameraAuthorization: AVAuthorizationStatus = .notDetermined
    @State private var pastedLink: String = ""
    @State private var showPasteField = false
    @State private var torchOn = false
    @State private var lastScannedString: String?
    @State private var showAttemptDetails = false

    public init() {}

    private var manager: ConnectionManager? { environment.connection as? ConnectionManager }

    public var body: some View {
        ZStack {
            scannerBackground
            VStack {
                topBar
                Spacer()
                bottomControls
            }
            .padding()

            if let progress = manager?.pairingProgress, progress != .idle {
                progressOverlay(progress)
            }
        }
        .background(Color.black)
        .onAppear { checkCameraAuthorization() }
        .onChange(of: manager?.pairingProgress) { _, newValue in
            guard case .paired = newValue else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
        }
    }

    // MARK: - Scanner

    @ViewBuilder
    private var scannerBackground: some View {
        switch cameraAuthorization {
        case .authorized:
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                DataScannerRepresentable(torchOn: torchOn, onScan: handleScannedString)
                    .ignoresSafeArea()
            } else {
                MetadataScannerRepresentable(torchOn: torchOn, onScan: handleScannedString)
                    .ignoresSafeArea()
            }
        case .denied, .restricted:
            cameraDeniedView
        default:
            Color.black.ignoresSafeArea()
        }
    }

    private var cameraDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.6))
            Text("Camera access needed", comment: "Pairing screen: camera denied title")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Allow camera access to scan the pairing code, or paste the pairing link instead.", comment: "Pairing screen: camera denied message")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings", comment: "Error recovery action: deep-links to iOS Settings for this app")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .black.opacity(0.4))
            }
            .accessibilityLabel(Text("Close", comment: "Pairing screen: close button"))

            Spacer()

            if cameraAuthorization == .authorized {
                Button {
                    torchOn.toggle()
                } label: {
                    Image(systemName: torchOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.title2)
                        .foregroundStyle(.white, .black.opacity(0.4))
                }
                .accessibilityLabel(Text("Torch", comment: "Pairing screen: torch toggle"))
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            if showPasteField {
                HStack {
                    TextField(String(localized: "Paste pairing link", comment: "Pairing screen: paste field placeholder"), text: $pastedLink)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { handleScannedString(pastedLink) }
                    Button(String(localized: "Go", comment: "Pairing screen: submit pasted link")) {
                        handleScannedString(pastedLink)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
                Button {
                    if let clipboardString = UIPasteboard.general.string {
                        pastedLink = clipboardString
                    }
                    showPasteField = true
                } label: {
                    Text("Paste pairing link", comment: "Pairing screen: reveals the paste field")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.9))
                .foregroundStyle(.black)
            }
        }
    }

    @ViewBuilder
    private func progressOverlay(_ progress: PairingProgress) -> some View {
        VStack(spacing: 16) {
            switch progress {
            case .idle:
                EmptyView()
            case .connecting(let hostName):
                ProgressView()
                Text(hostName.map { String(localized: "Connecting to \($0)…") } ?? String(localized: "Connecting…"))
                    .font(.headline)
            case .verifying(let hostName):
                ProgressView()
                Text("Pairing with \(hostName)…", comment: "Pairing screen: verifying state")
                    .font(.headline)
            case .paired(let hostName):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text("Paired", comment: "Pairing screen: success state")
                    .font(.headline)
                Text(hostName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .failed(let appError):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)
                Text(appError.presentation.title)
                    .font(.headline)
                Text(appError.presentation.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(String(localized: "Try again", comment: "Error recovery action: dismisses and lets the user rescan")) {
                    lastScannedString = nil
                    manager?.resetPairingProgress()
                }
                .buttonStyle(.borderedProminent)
                if let attempts = manager?.lastConnectionAttempts, !attempts.isEmpty {
                    attemptDetailsDisclosure(attempts)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.primary)
        .transition(.opacity)
    }

    /// spec §9 diagnostics deliverable: every candidate address tried, its outcome, and elapsed
    /// time — so a failed pair doesn't leave the user (or support) guessing what actually happened
    /// on the network, without needing Console.app on the Mac.
    @ViewBuilder
    private func attemptDetailsDisclosure(_ attempts: [AddressAttemptResult]) -> some View {
        DisclosureGroup(String(localized: "Details", comment: "Pairing screen: expands the per-address connection attempt log"), isExpanded: $showAttemptDetails) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(attempts) { attempt in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attempt.address)
                            .font(.caption.monospaced())
                        Text("\(attempt.outcome) · \(attempt.elapsedMs) ms")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 4)
        }
        .font(.footnote.weight(.medium))
        .frame(maxWidth: 260)
    }

    // MARK: - Handling

    private func checkCameraAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraAuthorization = status
        guard status == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                cameraAuthorization = granted ? .authorized : .denied
            }
        }
    }

    private func handleScannedString(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != lastScannedString else { return }
        guard trimmed.hasPrefix("\(PairingURLScheme.scheme)://\(PairingURLScheme.pairHost)?") else { return }
        lastScannedString = trimmed
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await manager?.pair(urlString: trimmed) }
    }
}

/// `PairingURL.scheme`/`.pairHost` are internal to `AirMouseProtocol`'s own type; this tiny mirror
/// avoids importing the whole module just to prefix-check a scanned string before handing it to
/// `ConnectionManager.pair(urlString:)` (which does the real parse/validate).
private enum PairingURLScheme {
    static let scheme = "airmouse"
    static let pairHost = "pair"
}

// MARK: - AVCaptureMetadataOutput fallback scanner

private struct MetadataScannerRepresentable: UIViewControllerRepresentable {
    let torchOn: Bool
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> MetadataScannerViewController {
        let controller = MetadataScannerViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: MetadataScannerViewController, context: Context) {
        uiViewController.setTorch(on: torchOn)
    }
}

private final class MetadataScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    // `nonisolated(unsafe)`: only ever set on `.main` (`makeUIViewController`, MainActor) and
    // read from `metadataOutput(...)`, which `setMetadataObjectsDelegate(_:queue: .main)` also
    // guarantees runs on `.main` — actually thread-safe despite the compiler being unable to
    // prove it across the `nonisolated` delegate protocol requirement.
    nonisolated(unsafe) var onScan: ((String) -> Void)?
    // `nonisolated(unsafe)`: only ever touched on the main thread (this controller's own methods,
    // all effectively `@MainActor`-run), but `deinit` is always `nonisolated` in Swift, and
    // `AVCaptureSession` isn't `Sendable` — this property needs to be readable from there.
    private nonisolated(unsafe) let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        guard session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func setTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    // Delivered on `.main` (see `setMetadataObjectsDelegate(_:queue:)` above), but the protocol
    // requirement itself is nonisolated — mark this `nonisolated` so the conformance typechecks
    // under Swift 6 strict concurrency (`UIViewController` subclasses are implicitly `@MainActor`).
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr, let string = object.stringValue else { return }
        onScan?(string)
    }

    deinit {
        session.stopRunning()
    }
}

// MARK: - VisionKit DataScannerViewController

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let torchOn: Bool
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: false
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        uiViewController.toggleTorch(torchOn)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onScan(payload)
                }
            }
        }
    }
}

private extension DataScannerViewController {
    func toggleTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}

#Preview {
    PairingScreen()
        .environment(\.appEnvironment, .preview())
}
