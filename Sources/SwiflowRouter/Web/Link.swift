// Sources/SwiflowRouter/Web/Link.swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// An in-app navigation link. Renders an `<a>` element whose click handler
/// calls `router.navigate(path)` and prevents full-page reload.
///
/// Two call shapes:
/// ```swift
/// Link("/about", "About")            // label variant
/// Link("/about") { img(...) }        // children variant
/// ```
public final class Link: Component {
    private enum Content {
        case label(String)
        case children([VNode])
    }

    private let path: String
    private let content: Content
    private let linkRef = Ref<JSObject>()
    private var clickClosure: JSClosure?
    // Reads AmbientEnvironment.current during body (set by the diff).
    // Must NOT be read in onAppear — that runs outside a body call and
    // would see the default no-op environment.
    @Environment(\.router) private var ambientRouter
    // Captured during body evaluation so onAppear can use the live router.
    private var capturedNavigate: (@Sendable (String) -> Void)?

    /// Label variant — renders `<a href="{path}">{label}</a>`.
    public init(_ path: String, _ label: String) {
        self.path = path
        self.content = .label(label)
    }

    /// Children variant — renders `<a href="{path}">{ children }</a>`.
    public init(_ path: String, @ChildrenBuilder _ children: () -> [VNode]) {
        self.path = path
        self.content = .children(children())
    }

    public var body: VNode {
        // Capture navigate during body — ambientRouter.wrappedValue reads
        // AmbientEnvironment.current which is set by the diff only during body.
        capturedNavigate = ambientRouter.navigate
        let refAttr = Attribute.refBinding(AnyRefBinding(linkRef))
        switch content {
        case .label(let text):
            return link(.attr("href", path), refAttr) { VNode.text(text) }
        case .children(let nodes):
            return link(.attr("href", path), refAttr) { nodes }
        }
    }

    public func onAppear() {
        let navigate = capturedNavigate ?? { _ in }
        let targetPath = path
        let closure = JSClosure { args -> JSValue in
            if let event = args.first?.object { _ = event.preventDefault!() }
            navigate(targetPath)
            return .undefined
        }
        if let el = linkRef.wrappedValue { _ = el.addEventListener!("click", closure) }
        clickClosure = closure
    }
}
#endif
