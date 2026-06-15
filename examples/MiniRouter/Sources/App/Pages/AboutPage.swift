import Swiflow
import SwiflowDOM
import SwiflowRouter
import SwiflowUI
import JavaScriptKit

final class AboutPage: Component {
    @Environment(\.router) var router

    var body: VNode {
        // Capture router.back inside body where AmbientEnvironment.current is set.
        // Accessing self.router from a click handler (outside body) would see the
        // default no-op.
        let back = router.back
        return VStack(spacing: .md, align: .start) {
            embed { NavBar() }
            h1("About")
            p("This demo exercises RouterRoot, Route, Link, and programmatic navigation.")
            Button("Back") { back() }
        }
        .padding(.lg)
    }
}
