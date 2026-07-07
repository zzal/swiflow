import Swiflow
import SwiflowDOM
import SwiflowRouter
import JavaScriptKit

final class NavBar: Component {
    var body: VNode {
        nav {
            embed { Link("/", "Home") }
            embed { Link("/about", "About") }
            // .prefix: stays lit on any /users/… child route — the usual
            // choice for a section link. The current page's Link renders
            // aria-current="page" (styled in index.html) + .sw-link-active.
            embed { Link("/users/42", "User 42", active: .prefix) }
        }
    }
}
