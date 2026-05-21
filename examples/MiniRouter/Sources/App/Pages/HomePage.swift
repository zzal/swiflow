import Swiflow
import SwiflowWeb
import JavaScriptKit

final class HomePage: Component {
    var body: VNode {
        div {
            embed { NavBar() }
            h1("Home")
            p("Welcome to the MiniRouter demo.")
        }
    }
}
