import Swiflow
import SwiflowDOM
import SwiflowRouter
import JavaScriptKit

final class NavBar: Component {
    var body: VNode {
        nav {
            embed { Link("/", "Home") }
            embed { Link("/about", "About") }
            embed { Link("/users/42", "User 42") }
        }
    }
}
