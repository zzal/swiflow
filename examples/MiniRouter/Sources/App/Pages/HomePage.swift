import Swiflow
import SwiflowDOM
import SwiflowUI
import JavaScriptKit

final class HomePage: Component {
    var body: VNode {
        VStack(spacing: .md, align: .start) {
            embed { NavBar() }
            h1("Home")
            p("Welcome to the MiniRouter demo.")
        }
        .padding(.lg)
    }
}
