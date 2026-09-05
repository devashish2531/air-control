// EventInjector+MediaKeys — spec §5.3.7 media keys (volume/brightness/mute/transport). CoreAudio-based
// `volume{level,mute}` handling is out of scope for this module (it isn't a `CGEvent`/media-key
// injection concern) and is left to whichever module owns host audio state; the SOUND_UP/DOWN
// key-stepping fallback that spec §5.3.7 describes for `volume` can be built on top of `mediaKey`
// below once that module exists.
import AirMouseProtocol

extension EventInjector {
    /// `down`/`up` — posts via `EventPosting.postSystemDefined`, which builds the
    /// `NSEvent(.systemDefined, subtype: 8, ...)` (research A4, spec §5.3.7).
    public func mediaKey(_ key: MediaKey, isDown: Bool) {
        guard !paused else {
            counters.droppedWhilePaused += 1
            return
        }
        noteActivity()
        guard rateLimiterAllows(.media) else { return }
        poster.postSystemDefined(nxKeyType: key.nxKeyType, isKeyDown: isDown)
        counters.mediaKeysPosted += 1
    }

    /// spec §5.3.7: "`tap` posts both 10 ms apart."
    public func mediaKeyTap(_ key: MediaKey) {
        mediaKey(key, isDown: true)
        scheduleAfter(Self.mediaKeyTapGap) { isolated in
            isolated.mediaKey(key, isDown: false)
        }
    }

    func rateLimiterAllows(_ category: InjectionCategory) -> Bool {
        guard let rateLimiter else { return true }
        if rateLimiter(category) { return true }
        counters.droppedByRateLimiter += 1
        return false
    }
}
