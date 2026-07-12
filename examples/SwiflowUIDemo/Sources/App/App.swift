import Swiflow
import SwiflowDOM
import SwiflowUI
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

@Component
final class Demo {
    @State var isDark: Bool = false

    var body: VNode {
        VStack(spacing: .lg, align: .stretch) {
            // A Toggle wired to `color-scheme` (synced to <html> in onChange) re-themes the
            // whole demo: every --sw-* token is light-dark(), so flipping the scheme flips them all.
            HStack(align: .center) {
                h1("SwiflowUI — primitives, controls & feedback")
                Spacer()
                Toggle("Dark mode", isOn: $isDark)
            }

            Divider()

            // --- Reducer wizard ------------------------------------------
            reducerWizardSection
        }
        .padding(.xl)
        .style("background", "var(--sw-bg)")   // page/canvas, so the surface cards lift off it
        .style("color", "var(--sw-text)")
        .style("min-height", "100vh")
    }

    // The "Dark mode" Toggle re-themes the demo by forcing `color-scheme` on the *document
    // root* (`<html>`). It must be `:root`, not a mounted element: the `--sw-*` color tokens are
    // registered via `@property { syntax: "<color>" }`, so their `light-dark()` resolves at the
    // element where they're declared (`:root`) — forcing `color-scheme` on an inner div has no
    // effect on them. Synced imperatively (idempotent read-diff-write) because the app tree can't
    // style `<html>`. JS-interop is `#if`-gated so the demo still builds on host.
    func onAppear() { syncColorScheme() }
    func onChange() { syncColorScheme() }

    private func syncColorScheme() {
        #if canImport(JavaScriptKit)
        guard let html = JSObject.global.document.object?.documentElement.object,
              let style = html.style.object else { return }
        let want = isDark ? "dark" : "light"
        if style.colorScheme.string != want { style.colorScheme = .string(want) }
        #endif
    }

    /// A two-step wizard backed by `@ReducerState`. Demonstrates sync dispatch
    /// and a fire-and-forget async effect at the call site (no `async` on the handler).
    var reducerWizardSection: VNode {
        VStack(spacing: .md, align: .stretch) {
            h2("Reducer wizard")
            p("A @ReducerState-backed two-step wizard. \"Next\" and \"Back\" are sync dispatches; "
              + "\"Submit\" fires an async effect (300 ms simulated round-trip) then dispatches "
              + "a second action when it completes. The reducer is pure; all async lives at the call site.")
            embed { SignupWizardView() }
        }
    }

}

// MARK: - Reducer wizard demo

struct SignupWizard: Reducer {
    struct State { var step = 0; var submitting = false; var done = false }
    enum Action { case next, back, submitStarted, submitFinished }
    var initialState: State { .init() }
    func reduce(into s: inout State, _ a: Action) {
        switch a {
        case .next where s.step < 1: s.step += 1
        case .back where s.step > 0: s.step -= 1
        case .submitStarted: s.submitting = true
        case .submitFinished: s.submitting = false; s.done = true
        default: break
        }
    }
}

@Component
final class SignupWizardView {
    @ReducerState var wiz: SignupWizard
    var body: VNode {
        let s = $wiz.state
        return VStack(spacing: .md, align: .stretch) {
            if s.done {
                p("Done ✓")
            } else {
                p("Step \(s.step + 1) of 2")
                HStack(spacing: .sm, align: .center) {
                    Button("Back", variant: .secondary, disabled: s.step == 0) { self.$wiz.send(.back) }
                    if s.step < 1 {
                        Button("Next") { self.$wiz.send(.next) }
                    } else {
                        Button("Submit", disabled: s.submitting) {
                            self.$wiz.send(.submitStarted)
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(300))
                                self.$wiz.send(.submitFinished)
                            }
                        }
                    }
                }
            }
        }
        .padding(.md)
        .style("background", Token.surface)
        .style("border-radius", Token.radius)
    }
}

@main
struct App {
    @MainActor static func main() { Swiflow.render(into: "#app") { Shell() } }
}
