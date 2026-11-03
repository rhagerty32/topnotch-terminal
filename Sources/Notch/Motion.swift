import AppKit
import QuartzCore

@MainActor
enum Motion {
    static var gush: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.18, 1.16, 0.22, 1)
    }

    static var gushOut: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1)
    }

    static func run(
        animated: Bool,
        expanding: Bool = true,
        duration: TimeInterval? = nil,
        animations: @escaping () -> Void,
        completion: (() -> Void)? = nil
    ) {
        let reduce = AppSettings.shared.reduceMotion
        guard animated, !reduce else {
            animations()
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration ?? (expanding ? 0.62 : 0.36)
            ctx.timingFunction = expanding ? gush : gushOut
            ctx.allowsImplicitAnimation = true
            animations()
        }, completionHandler: completion)
    }
}

/// Springs width and height only. Top stays glued to the notch; growth is downward.
@MainActor
final class RectSpring {
    private var timer: Timer?
    private var lastTime: CFTimeInterval = 0
    private var w = 0.0
    private var h = 0.0
    private var vw = 0.0
    private var vh = 0.0
    private var tw = 0.0
    private var th = 0.0
    private var topY = 0.0
    private var midX = 0.0
    private var expanding = true
    private var onTick: ((NSRect) -> Void)?
    private var onDone: (() -> Void)?

    var isRunning: Bool { timer != nil }

    var currentRect: NSRect {
        pinnedRect(width: w, height: h)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        onTick = nil
        onDone = nil
    }

    func animate(
        from: NSRect,
        to: NSRect,
        expanding: Bool,
        tick: @escaping (NSRect) -> Void,
        completion: (() -> Void)? = nil
    ) {
        cancel()
        if AppSettings.shared.reduceMotion {
            tick(to)
            completion?()
            return
        }

        self.expanding = expanding
        topY = to.maxY
        midX = to.midX
        w = from.size.width
        h = from.size.height
        tw = to.size.width
        th = to.size.height
        let dirW = tw - w
        let dirH = th - h
        vw = expanding ? dirW * 1.15 : dirW * 1.05
        vh = expanding ? dirH * 1.05 : dirH * 1.15
        onTick = tick
        onDone = completion
        lastTime = CACurrentMediaTime()
        tick(pinnedRect(width: w, height: h))

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.step()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func pinnedRect(width: Double, height: Double) -> NSRect {
        let w = max(1, width)
        let h = max(1, height)
        return NSRect(x: midX - w / 2, y: topY - h, width: w, height: h)
    }

    private func step() {
        let now = CACurrentMediaTime()
        var dt = now - lastTime
        lastTime = now
        if dt <= 0 { return }
        dt = min(dt, 1.0 / 30.0)

        let widthK: Double = expanding ? 280 : 310
        let widthD: Double = expanding ? 25 : 28
        let heightK: Double = expanding ? 265 : 300
        let heightD: Double = expanding ? 24 : 27

        integrate(value: &w, velocity: &vw, target: tw, stiffness: widthK, damping: widthD, dt: dt)
        integrate(value: &h, velocity: &vh, target: th, stiffness: heightK, damping: heightD, dt: dt)

        let rect = currentRect
        onTick?(rect)

        let settled =
            abs(w - tw) < 0.35 && abs(h - th) < 0.35 &&
            abs(vw) < 10 && abs(vh) < 10

        if settled {
            let done = onDone
            let tick = onTick
            cancel()
            tick?(pinnedRect(width: tw, height: th))
            done?()
        }
    }

    private func integrate(
        value: inout Double,
        velocity: inout Double,
        target: Double,
        stiffness: Double,
        damping: Double,
        dt: Double
    ) {
        let accel = -stiffness * (value - target) - damping * velocity
        velocity += accel * dt
        value += velocity * dt
    }
}
