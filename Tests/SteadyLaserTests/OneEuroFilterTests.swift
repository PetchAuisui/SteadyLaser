import CoreGraphics
import XCTest
@testable import SteadyLaser

/// The same scenario as `SteadyLaser --selftest`, with pass/fail limits:
/// a hand-held air mouse at 120 Hz with ±3 px tremor, then a 1500 px/s sweep.
final class OneEuroFilterTests: XCTestCase {
    private struct Result { var jitterLeft: Double; var lagMs: Double }

    private func run(_ stability: Stability) -> Result {
        // Fixed tremor pattern so the numbers don't change between runs.
        var seed: UInt64 = 0x5EED
        func tremor() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(Int(seed >> 33) % 7 - 3)
        }

        var f = OneEuroFilter2D(minCutoff: stability.minCutoff, beta: stability.beta)
        let dt = 1.0 / 120.0
        var t = 0.0
        var inSpread = 0.0, outSpread = 0.0
        var prevIn = CGPoint(x: 500, y: 500), prevOut = prevIn
        for i in 0..<240 {
            let p = CGPoint(x: 500 + tremor(), y: 500 + tremor())
            let o = f.filter(p, time: t)
            if i > 30 {
                inSpread += hypot(p.x - prevIn.x, p.y - prevIn.y)
                outSpread += hypot(o.x - prevOut.x, o.y - prevOut.y)
            }
            prevIn = p; prevOut = o; t += dt
        }

        var x = 500.0, lag = 0.0
        for _ in 0..<60 {
            x += 1500 * dt
            lag = x - f.filter(CGPoint(x: x, y: 500), time: t).x
            t += dt
        }
        return Result(jitterLeft: outSpread / inSpread, lagMs: lag / 1500 * 1000)
    }

    func testMediumRemovesMostTremorWithLittleLag() {
        let r = run(.medium)
        XCTAssertLessThan(r.jitterLeft, 0.15, "medium should remove at least 85% of tremor")
        XCTAssertLessThan(r.lagMs, 15, "medium should trail a fast sweep by under 15 ms")
    }

    func testSteadierSettingsSmoothMore() {
        let low = run(.low), medium = run(.medium), high = run(.high)
        XCTAssertLessThan(medium.jitterLeft, low.jitterLeft)
        XCTAssertLessThan(high.jitterLeft, medium.jitterLeft)
        XCTAssertLessThan(high.lagMs, 40, "even the steadiest setting must keep up with a sweep")
    }

    func testFirstSampleAndResetPassThrough() {
        var f = OneEuroFilter2D(minCutoff: 1.8, beta: 0.006)
        XCTAssertEqual(f.filter(CGPoint(x: 10, y: 20), time: 0), CGPoint(x: 10, y: 20))
        _ = f.filter(CGPoint(x: 15, y: 20), time: 0.01)
        f.reset()
        XCTAssertEqual(f.filter(CGPoint(x: 900, y: 40), time: 0.02), CGPoint(x: 900, y: 40))
    }
}
