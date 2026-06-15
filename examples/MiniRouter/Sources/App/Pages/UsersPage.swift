import Swiflow
import SwiflowDOM
import SwiflowRouter
import SwiflowUI
import JavaScriptKit

final class UsersPage: Component {
    let userId: String
    @Environment(\.router) var router

    init(userId: String) {
        self.userId = userId
    }

    var body: VNode {
        // Read router.navigate HERE inside body, where AmbientEnvironment.current
        // is set by the diff. Accessing self.router from a click handler (outside
        // body) would see the default no-op.
        let navigate = router.navigate
        return VStack(spacing: .md, align: .start) {
            embed { NavBar() }
            h1("User: \(userId)")
            p("Loaded via the :id route param.")
            Button("Go Home") { navigate("/") }
        }
        .padding(.lg)
    }
}
