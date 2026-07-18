// Sources/App/FlowCanvas.swift
//
// The one canvas layer: flow particles along the interconnect arcs,
// painted imperatively every frame through the .ref seam. Swiflow never
// reconciles inside the canvas — it only owns the element shell.
//
// Bridge-chattiness budget: ≤ ~40 particles/edge × 14 edges ≈ 560
// particles, one beginPath+arc+fill batch PER EDGE (15 fill calls, not
// 560). If the Task 15 perf checkpoint shows dropped frames, halve
// PARTICLE_BUDGET before reaching for lineDashOffset streams.
import Swiflow
import JavaScriptKit
import GridCore

private let PARTICLE_BUDGET = 40                 // max per edge

extension GridShell {
    @MainActor
    func drawFlows() {
        guard let snap = snapshot else { return }
        if canvasCtx == nil, let canvas = canvasRef.wrappedValue {
            canvasCtx = canvas.getContext!("2d").object
            particlePhases = Interconnect.all.indices.map { i in
                var rng = SplitMix64(seed: UInt64(1000 + i))
                return (0..<PARTICLE_BUDGET).map { _ in rng.unit() }
            }
        }
        guard let ctx = canvasCtx else { return }
        _ = ctx.clearRect!(0, 0, MapGeometry.viewWidth, MapGeometry.viewHeight)

        for (i, tie) in Interconnect.all.enumerated() {
            let mean = snap.edges[i].meanFlowMW
            let load = min(1, abs(mean) / tie.capacityMW)
            guard load > 0.01 else { continue }
            let count = max(2, Int(Double(PARTICLE_BUDGET) * load))
            let speed = (0.001 + 0.006 * load) * (mean >= 0 ? 1 : -1)
            let (p0, c, p1) = arcControlPoints(i)

            ctx.fillStyle = .string(mean >= 0 ? "rgba(96, 165, 250, 0.85)" : "rgba(251, 146, 60, 0.85)")
            _ = ctx.beginPath!()
            for p in 0..<count {
                particlePhases[i][p] += speed
                if particlePhases[i][p] > 1 { particlePhases[i][p] -= 1 }
                if particlePhases[i][p] < 0 { particlePhases[i][p] += 1 }
                let u = particlePhases[i][p]
                // Quadratic bezier point.
                let v = 1 - u
                let x = v * v * p0.0 + 2 * v * u * c.0 + u * u * p1.0
                let y = v * v * p0.1 + 2 * v * u * c.1 + u * u * p1.1
                _ = ctx.moveTo!(x + 2.2, y)
                _ = ctx.arc!(x, y, 2.2, 0, 6.2832)
            }
            _ = ctx.fill!()
        }
    }
}
