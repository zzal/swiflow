// Sources/App/PerfHUD.swift
//
// The receipts: dataset size, rows touched by the LAST query, its
// elapsed ms, live fps, and the startup generation time. Collapsible so
// screenshots can go chrome-less.
import Swiflow
import SwiflowUI
import GridCore

extension GridShell {
    @MainActor
    func fmtPts(_ n: Int) -> String {
        if n >= 1_000_000 {
            let tenths = (n * 10) / 1_000_000
            return "\(tenths / 10).\(tenths % 10)M"
        }
        if n >= 1_000 { return "\(n / 1_000)k" }
        return "\(n)"
    }

    @MainActor
    func fmtMs(_ ms: Double) -> String {
        let tenths = Int((ms * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)"
    }

    @MainActor
    func hudView() -> VNode {
        let datasetPts = GridDataset.intervalCount * Zone.allCases.count * 9
        var children: [VNode] = [
            Button(hudOpen ? "⌄" : "⌃", variant: .ghost, size: .xs) { [weak self] in
                self?.hudOpen.toggle()
            },
        ]
        if hudOpen {
            let stats = snapshot?.stats
            children.append(element("dl", attributes: [.class("gb-hud-grid")], children: [
                hudCell(fmtPts(datasetPts), "dataset pts"),
                hudCell(stats.map { fmtPts($0.rowsTouched) } ?? "—", "rows / query"),
                hudCell(stats.map { "\(fmtMs($0.elapsedMs)) ms" } ?? "—", "scan time"),
                hudCell("\(hudFps)", "fps"),
                hudCell("\(Int(buildMs.rounded())) ms", "generated in"),
            ]))
        }
        return Card(variant: .outlined, .class("gb-hud")) { children }
    }

    @MainActor
    private func hudCell(_ value: String, _ label: String) -> VNode {
        element("div", attributes: [.class("gb-hud-cell")], children: [
            element("dt", attributes: [], children: [text(label)]),
            element("dd", attributes: [], children: [text(value)]),
        ])
    }
}
