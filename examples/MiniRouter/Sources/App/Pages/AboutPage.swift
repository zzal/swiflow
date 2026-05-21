import Swiflow
import SwiflowWeb
import JavaScriptKit

final class AboutPage: Component {
    var body: VNode {
        div {
            embed { NavBar() }
            h1("About")
            p("This demo exercises RouterRoot, Route, Link, and programmatic navigation.")
        }
    }
}
