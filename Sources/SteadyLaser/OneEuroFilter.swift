import CoreGraphics
import QuartzCore

/// 2D One Euro filter (Casiez et al., CHI 2012).
///
/// Strong smoothing when the pointer is slow (kills hand tremor), and the
/// cutoff opens up with speed so fast sweeps don't lag. Speed is measured as
/// a 2D magnitude so smoothing is the same in every direction.
struct OneEuroFilter2D {
    var minCutoff: Double
    var beta: Double
    var derivativeCutoff: Double = 1.0

    private var last: CGPoint?
    private var velocity = CGVector.zero
    private var lastTime: CFTimeInterval = 0

    init(minCutoff: Double, beta: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    mutating func reset() {
        last = nil
        velocity = .zero
    }

    private static func alpha(dt: Double, cutoff: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    mutating func filter(_ p: CGPoint, time t: CFTimeInterval) -> CGPoint {
        guard let prev = last else {
            last = p
            lastTime = t
            velocity = .zero
            return p
        }
        // Clamp dt so a stalled frame can't produce a huge jump or a divide by ~0.
        let dt = min(max(t - lastTime, 1.0 / 1000.0), 0.1)
        lastTime = t

        let rawVelocity = CGVector(dx: (p.x - prev.x) / dt, dy: (p.y - prev.y) / dt)
        let ad = Self.alpha(dt: dt, cutoff: derivativeCutoff)
        velocity = CGVector(
            dx: velocity.dx + ad * (rawVelocity.dx - velocity.dx),
            dy: velocity.dy + ad * (rawVelocity.dy - velocity.dy)
        )

        let speed = hypot(velocity.dx, velocity.dy)
        let a = Self.alpha(dt: dt, cutoff: minCutoff + beta * speed)
        let out = CGPoint(x: prev.x + a * (p.x - prev.x), y: prev.y + a * (p.y - prev.y))
        last = out
        return out
    }
}
