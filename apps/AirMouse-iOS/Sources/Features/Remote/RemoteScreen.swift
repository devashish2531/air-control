// Features/Remote/RemoteScreen.swift
// Remote tab per spec §4.1.7: segmented Presenter / Media. Replaces the placeholder. Large,
// glance-free touch targets throughout (spec §4.8, A11y.minimumTapTarget); iPad (regular width)
// lays buttons out as a two-column grid per this agent's assignment ("iPad: two-column grid").

import SwiftUI
import Foundation
import AirMouseProtocol

public struct RemoteScreen: View {
    @Environment(\.appEnvironment) private var contextEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var model: RemoteModel?

    private let injectedEnvironment: AppEnvironment?
    private let sink: any RemoteCommandSink

    /// Zero-argument entry point kept for `RootTabView.swift`'s current (unmodified) call site
    /// `case .remote: RemoteScreen()`. Reads the real `AppEnvironment` from the SwiftUI
    /// environment and falls back to `NoOpRemoteCommandSink` until the integration agent switches
    /// this call site to `RemoteFeature.make(environment:sink:)` with a real sink.
    public init(sink: any RemoteCommandSink = NoOpRemoteCommandSink()) {
        self.injectedEnvironment = nil
        self.sink = sink
    }

    /// Used by `RemoteFeature.make(environment:sink:)` (Features/Remote/RemoteFeature+Environment.swift).
    init(environment: AppEnvironment, sink: any RemoteCommandSink) {
        self.injectedEnvironment = environment
        self.sink = sink
    }

    private var environment: AppEnvironment { injectedEnvironment ?? contextEnvironment }

    public var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                Color.clear
            }
        }
        .task {
            guard model == nil else { return }
            let haptics = environment.haptics
            model = RemoteModel(
                sink: sink,
                haptics: haptics,
                idleDimSecondsProvider: { [environment] in environment.userSettings.snapshot.remote.presenterIdleDimSeconds }
            )
        }
        .navigationTitle(Text("Remote", comment: "Remote tab navigation title"))
    }

    @ViewBuilder
    private func content(model: RemoteModel) -> some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(get: { model.segment }, set: { model.segment = $0 })) {
                ForEach(RemoteSegment.allCases) { segment in
                    Text(segment.title).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            .accessibilityLabel(Text("Remote mode", comment: "Accessibility label for the Presenter/Media segmented control"))

            ScrollView {
                Group {
                    switch model.segment {
                    case .presenter:
                        PresenterSegmentView(model: model, twoColumn: horizontalSizeClass == .regular)
                    case .media:
                        MediaSegmentView(model: model, twoColumn: horizontalSizeClass == .regular)
                    }
                }
                .padding()
            }
        }
        .opacity(model.segment == .presenter && model.isDimmed ? 0.2 : 1)
        .animation(.easeInOut(duration: 0.3), value: model.isDimmed)
        .contentShape(Rectangle())
        .onTapGesture { model.recordActivity() }
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in model.recordActivity() })
        .task {
            model.recordActivity()
            await model.loadMediaLauncherButtons()
        }
        .onDisappear { model.stopIdleDimTracking() }
        .airMouseDynamicTypeRange()
    }
}

// MARK: - Presenter

private struct PresenterSegmentView: View {
    let model: RemoteModel
    let twoColumn: Bool
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        VStack(spacing: 20) {
            header

            // spec §4.1.7: "big Previous (left 40 %) and Next (right 60 %) in the lower half."
            GeometryReader { geometry in
                HStack(spacing: 12) {
                    RemoteButton(title: String(localized: "Previous", comment: "Presenter previous slide button"), systemImage: "arrow.left", haptics: environment.haptics) {
                        model.previousSlide()
                    }
                    .frame(width: (geometry.size.width - 12) * 0.4)

                    RemoteButton(title: String(localized: "Next", comment: "Presenter next slide button"), systemImage: "arrow.right", haptics: environment.haptics) {
                        model.nextSlide()
                    }
                    .frame(width: (geometry.size.width - 12) * 0.6)
                }
            }
            .frame(minHeight: 120)

            actionGrid

            PresenterTimerCard(timer: model.timer)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(model.frontmostAppName ?? String(localized: "No Mac connected", comment: "Presenter header when no frontmost app is known"))
                .font(.headline)
            Text(model.presenterProfile.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var actionGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: twoColumn ? 2 : 4)
        return LazyVGrid(columns: columns, spacing: 12) {
            RemoteButton(title: String(localized: "Blank", comment: "Presenter blank/black screen button (B key)"), systemImage: "rectangle.slash", haptics: environment.haptics) {
                model.blankScreen()
            }
            RemoteButton(title: String(localized: "Start", comment: "Presenter start-from-current button"), systemImage: "play.fill", haptics: environment.haptics) {
                model.startPresentation()
            }
            RemoteButton(title: String(localized: "Exit", comment: "Presenter exit presentation button (Esc key)"), systemImage: "xmark", haptics: environment.haptics) {
                model.exitPresentation()
            }
            RemoteButton(title: String(localized: "Pointer", comment: "Presenter pointer-spotlight toggle button"), systemImage: "dot.circle.and.cursorarrow", haptics: environment.haptics) {
                model.togglePointerSpotlight()
            }
            .accessibilityHint(Text("Switches to the Touchpad tab", comment: "Accessibility hint for the presenter Pointer button"))
        }
    }
}

private struct PresenterTimerCard: View {
    @Bindable var timer: PresenterTimerModel

    var body: some View {
        VStack(spacing: 12) {
            Text(formatted(timer.remainingSeconds ?? timer.elapsedSeconds))
                .font(.system(.largeTitle, design: .monospaced))
                .monospacedDigit()
                .accessibilityLabel(Text("Presenter timer", comment: "Accessibility label for the presenter timer display"))

            HStack(spacing: 12) {
                Button(timer.isRunning ? String(localized: "Pause", comment: "Presenter timer pause button") : String(localized: "Start", comment: "Presenter timer start button")) {
                    timer.isRunning ? timer.pause() : timer.start()
                }
                .minimumTapTarget()

                Button(String(localized: "Reset", comment: "Presenter timer reset button")) {
                    timer.reset()
                }
                .minimumTapTarget()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatted(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Media

private struct MediaSegmentView: View {
    let model: RemoteModel
    let twoColumn: Bool
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        VStack(spacing: 20) {
            transportRow
            seekRow
            volumeRow
            brightnessRow
            launcherGrid
        }
    }

    private var transportRow: some View {
        HStack(spacing: 12) {
            RemoteButton(title: String(localized: "Previous", comment: "Media previous track button"), systemImage: "backward.fill", haptics: environment.haptics) {
                model.mediaPrevious()
            }
            .accessibilityIdentifier("remote.previous")
            RemoteButton(title: String(localized: "Play / Pause", comment: "Media play/pause button"), systemImage: "playpause.fill", haptics: environment.haptics) {
                model.mediaPlayPause()
            }
            .accessibilityIdentifier("remote.playPause")
            RemoteButton(title: String(localized: "Next", comment: "Media next track button"), systemImage: "forward.fill", haptics: environment.haptics) {
                model.mediaNext()
            }
            .accessibilityIdentifier("remote.next")
        }
    }

    private var seekRow: some View {
        HStack(spacing: 12) {
            RemoteButton(title: String(localized: "-10s", comment: "Media seek backward 10 seconds button"), systemImage: "gobackward.10", haptics: environment.haptics) {
                model.seekBackward()
            }
            RemoteButton(title: String(localized: "+10s", comment: "Media seek forward 10 seconds button"), systemImage: "goforward.10", haptics: environment.haptics) {
                model.seekForward()
            }
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 12) {
            RepeatingRemoteButton(title: String(localized: "Volume down", comment: "Media volume down button, hold to repeat"), systemImage: "speaker.minus.fill", haptics: environment.haptics, onPress: model.startVolumeDown, onRelease: model.stopVolumeRepeat)
                .accessibilityIdentifier("remote.volumeDown")
            RemoteButton(title: String(localized: "Mute", comment: "Media mute button"), systemImage: "speaker.slash.fill", haptics: environment.haptics) {
                model.mute()
            }
            RepeatingRemoteButton(title: String(localized: "Volume up", comment: "Media volume up button, hold to repeat"), systemImage: "speaker.plus.fill", haptics: environment.haptics, onPress: model.startVolumeUp, onRelease: model.stopVolumeRepeat)
                .accessibilityIdentifier("remote.volumeUp")
        }
    }

    private var brightnessRow: some View {
        HStack(spacing: 12) {
            RepeatingRemoteButton(title: String(localized: "Brightness down", comment: "Media brightness down button, hold to repeat"), systemImage: "sun.min.fill", haptics: environment.haptics, onPress: model.startBrightnessDown, onRelease: model.stopBrightnessRepeat)
            RepeatingRemoteButton(title: String(localized: "Brightness up", comment: "Media brightness up button, hold to repeat"), systemImage: "sun.max.fill", haptics: environment.haptics, onPress: model.startBrightnessUp, onRelease: model.stopBrightnessRepeat)
        }
    }

    @ViewBuilder
    private var launcherGrid: some View {
        if !model.mediaLauncherButtons.isEmpty {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: twoColumn ? 2 : 4)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.mediaLauncherButtons) { button in
                    RemoteButton(title: button.macro.name, systemImage: button.macro.icon, haptics: environment.haptics) {
                        Task { await invoke(button.macro) }
                    }
                }
            }
        }
    }

    private func invoke(_ macro: Macro) async {
        // Fire-and-forget from the Remote tab's launcher row: the Macros tab owns confirmation-
        // sheet UX and toast/error presentation (spec §4.1.8); a media-page launcher button never
        // targets a script macro in practice (script macros aren't `launchApp`), but as a safety
        // net this never sends `confirmed: true` on the caller's behalf — a macro that
        // `requiresConfirmation` is simply not invoked from here.
        guard !macro.requiresConfirmation else { return }
        await model.invokeLauncherMacro(macro)
    }
}

// MARK: - Shared button styles

private struct RemoteButton: View {
    let title: String
    let systemImage: String
    let haptics: any HapticsService
    let action: () -> Void

    var body: some View {
        Button {
            haptics.fire(.tapClick)
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: A11y.minimumTapTarget)
            .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .minimumTapTarget()
        .onAppear { haptics.prepare(.tapClick) }
        .accessibleButton(label: LocalizedStringKey(title))
    }
}

private struct RepeatingRemoteButton: View {
    let title: String
    let systemImage: String
    let haptics: any HapticsService
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: A11y.minimumTapTarget)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .background(.tertiary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .minimumTapTarget()
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    haptics.fire(.buttonDown)
                    onPress()
                }
                .onEnded { _ in
                    haptics.fire(.buttonUp)
                    onRelease()
                }
        )
        .accessibleButton(label: LocalizedStringKey(title), hint: "Hold to repeat")
    }
}

#Preview {
    NavigationStack { RemoteScreen() }
        .environment(\.appEnvironment, .preview())
}
