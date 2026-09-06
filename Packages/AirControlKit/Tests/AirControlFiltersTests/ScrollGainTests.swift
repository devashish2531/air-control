import Testing
@testable import AirControlFilters

@Suite struct ScrollGainTests {
    @Test func gainEndpointsMatchSpec() {
        #expect(abs(ScrollGain.gain(speed: 1) - 0.5) < 1e-9)
        #expect(abs(ScrollGain.gain(speed: 10) - 3.0) < 1e-9)
    }

    @Test func gainIsMonotonicIncreasing() {
        var last = ScrollGain.gain(speed: 1)
        for s in 2...10 {
            let value = ScrollGain.gain(speed: Double(s))
            #expect(value > last)
            last = value
        }
    }

    @Test func gainClamps() {
        #expect(ScrollGain.gain(speed: -10) == ScrollGain.gain(speed: 1))
        #expect(ScrollGain.gain(speed: 100) == ScrollGain.gain(speed: 10))
    }

    @Test func eighthPointConversionDividesByEight() {
        let sg = ScrollGain(scrollSpeed: 5, invertForNatural: false)
        let wire = Delta(dx: 8, dy: 16) // 1pt, 2pt in eighth-point units
        let px = sg.pixels(fromEighthPointDelta: wire)
        #expect(abs(px.dx - 1 * sg.gain) < 1e-9)
        #expect(abs(px.dy - 2 * sg.gain) < 1e-9)
    }

    @Test func naturalScrollInvertsBothAxes() {
        let normal = ScrollGain(scrollSpeed: 5, invertForNatural: false)
        let natural = ScrollGain(scrollSpeed: 5, invertForNatural: true)
        let delta = Delta(dx: 8, dy: -8)
        let a = normal.pixels(fromEighthPointDelta: delta)
        let b = natural.pixels(fromEighthPointDelta: delta)
        #expect(abs(a.dx + b.dx) < 1e-9)
        #expect(abs(a.dy + b.dy) < 1e-9)
    }

    @Test func pointDeltaConversionSkipsEighthDivision() {
        let sg = ScrollGain(scrollSpeed: 5)
        let pointDelta = Delta(dx: 2, dy: 0)
        let px = sg.pixels(fromPointDelta: pointDelta)
        #expect(abs(px.dx - 2 * sg.gain) < 1e-9)
    }
}
