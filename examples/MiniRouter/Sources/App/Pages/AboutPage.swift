import Swiflow
import SwiflowWeb
import SwiflowRouter
import JavaScriptKit

final class AboutPage: Component {
    @Environment(\.router) var router

    var body: VNode {
        // Capture router.back inside body where AmbientEnvironment.current is set.
        // Accessing self.router from a click handler (outside body) would see the
        // default no-op.
        let back = router.back
        return div {
            embed { NavBar() }
            h1("About")
            p("This demo exercises RouterRoot, Route, Link, and programmatic navigation.")
            button("Back", .on(.click) { _ in back() })
        }
    }
}
