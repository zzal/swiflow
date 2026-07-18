// Sources/App/FlowCanvas.swift
//
// The one canvas layer: flow particles along the interconnect arcs,
// painted imperatively every frame through the .ref seam. Swiflow never
// reconciles inside the canvas — it only owns the element shell.
//
// The electricity look is three tricks, all cheap:
//   1. Instead of clearRect, the previous frame is FADED with a
//      destination-out fill — particles leave short comet trails.
//   2. Dots draw twice under `lighter` (additive) compositing: a wide
//      soft halo plus a hot core, so overlapping particles bloom.
//   3. Each particle twinkles — its radius/alpha wobbles on a phase
//      offset — which reads as sparking.
//
// Bridge-chattiness budget: ≤ ~40 particles/edge × 14 edges ≈ 560
// particles, one beginPath+arc batch per edge PER PASS (≈30 fills a
// frame, not 1100). If frames drop, halve PARTICLE_BUDGET first.
import Swiflow
import JavaScriptKit
import GridCore

private let PARTICLE_BUDGET = 40                 // max per edge

extension GridShell {
    @MainActor
    func drawFlows(_ ts: Double) {
        guard let snap = snapshot else { return }
        if canvasCtx == nil, let canvas = canvasRef.wrappedValue {
            canvasCtx = canvas.getContext!("2d").object
            particlePhases = Interconnect.all.indices.map { i in
                var rng = SplitMix64(seed: UInt64(1000 + i))
                return (0..<PARTICLE_BUDGET).map { _ in rng.unit() }
            }
        }
        guard let ctx = canvasCtx else { return }

        // Fade last frame instead of clearing it — the residue is the trail.
        ctx.globalCompositeOperation = .string("destination-out")
        ctx.fillStyle = .string("rgba(0, 0, 0, 0.28)")
        _ = ctx.fillRect!(0, 0, MapGeometry.viewWidth, MapGeometry.viewHeight)

        // Additive from here on: overlaps bloom like light, not paint.
        ctx.globalCompositeOperation = .string("lighter")

        for (i, tie) in Interconnect.all.enumerated() {
            let mean = snap.edges[i].meanFlowMW
            let load = min(1, abs(mean) / tie.capacityMW)
            guard load > 0.01 else { continue }
            let count = max(2, Int(Double(PARTICLE_BUDGET) * load))
            let speed = (0.001 + 0.006 * load) * (mean >= 0 ? 1 : -1)
            let (p0, c, p1) = arcControlPoints(i)

            // Advance phases + evaluate bezier positions once per particle.
            var xs = [Double](repeating: 0, count: count)
            var ys = [Double](repeating: 0, count: count)
            var tw = [Double](repeating: 0, count: count)
            for p in 0..<count {
                particlePhases[i][p] += speed
                if particlePhases[i][p] > 1 { particlePhases[i][p] -= 1 }
                if particlePhases[i][p] < 0 { particlePhases[i][p] += 1 }
                let u = particlePhases[i][p]
                let v = 1 - u
                xs[p] = v * v * p0.0 + 2 * v * u * c.0 + u * u * p1.0
                ys[p] = v * v * p0.1 + 2 * v * u * c.1 + u * u * p1.1
                // Twinkle: each particle flickers on its own beat.
                tw[p] = 0.62 + 0.38 * _sinD(ts * 0.012 + Double(p) * 2.399)
            }

            let exporting = mean >= 0
            // Pass 1: soft halo.
            ctx.fillStyle = .string(exporting ? "rgba(96, 165, 250, 0.16)" : "rgba(251, 146, 60, 0.16)")
            _ = ctx.beginPath!()
            for p in 0..<count {
                let r = 4.6 * tw[p]
                _ = ctx.moveTo!(xs[p] + r, ys[p])
                _ = ctx.arc!(xs[p], ys[p], r, 0, 6.2832)
            }
            _ = ctx.fill!()
            // Pass 2: hot core.
            ctx.fillStyle = .string(exporting ? "rgba(190, 225, 255, 0.9)" : "rgba(255, 214, 160, 0.9)")
            _ = ctx.beginPath!()
            for p in 0..<count {
                let r = 1.7 * tw[p]
                _ = ctx.moveTo!(xs[p] + r, ys[p])
                _ = ctx.arc!(xs[p], ys[p], r, 0, 6.2832)
            }
            _ = ctx.fill!()
        }

        ctx.globalCompositeOperation = .string("source-over")
    }
}
