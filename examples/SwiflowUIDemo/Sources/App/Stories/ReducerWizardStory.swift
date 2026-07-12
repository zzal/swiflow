import Swiflow
import SwiflowUI

@Component
final class ReducerWizardStory {
    var body: VNode {
        storyPage("Reducer wizard",
                  blurb: "A @ReducerState-backed two-step wizard. \"Next\" and \"Back\" are sync dispatches; "
                       + "\"Submit\" fires an async effect (300 ms simulated round-trip) then dispatches "
                       + "a second action when it completes. The reducer is pure; all async lives at the call site.") {
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
