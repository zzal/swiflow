// Sources/App/NotFoundPage.swift
import Swiflow
import SwiflowDOM
import SwiflowRouter

/// Rendered by `RouterRoot`'s `notFound:` closure whenever no route matches —
/// without it, unmatched paths show the framework's plain diagnostic text.
/// Renders inside the router environment, so the Link home just works.
final class NotFoundPage: Component {
    private let path: String

    init(path: String) {
        self.path = path
    }

    var body: VNode {
        div {
            h1("Page not found")
            p("Nothing lives at \(path).")
            embed { Link("/", "Go home") }
        }
    }
}
