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
    private let activeMatch: LinkActiveMatch
    private let linkRef = Ref<JSObject>()
    private var clickClosure: JSClosure?
    // Reads AmbientEnvironment.current during body (set by the diff).
    // Must NOT be read in onAppear — that runs outside a body call and
    // would see the default no-op environment.
    @Environment(\.router) private var ambientRouter
    // Captured during body evaluation so onAppear can use the live router.
    private var capturedNavigate: (@Sendable (String) -> Void)?

    /// Label variant — renders `<a href="{path}">{label}</a>`.
    /// `active:` picks the current-page marking rule (see `LinkActiveMatch`);
    /// `.prefix` is the usual choice for section navs.
    public init(_ path: String, _ label: String, active: LinkActiveMatch = .exact) {
        self.path = path
        self.content = .label(label)
        self.activeMatch = active
    }

    /// Children variant — renders `<a href="{path}">{ children }</a>`.
    public init(_ path: String, active: LinkActiveMatch = .exact, @ChildrenBuilder _ children: () -> [VNode]) {
        self.path = path
        self.content = .children(children())
        self.activeMatch = active
    }

    public var body: VNode {
        // Capture navigate during body — ambientRouter.wrappedValue reads
        // AmbientEnvironment.current which is set by the diff only during body.
        capturedNavigate = ambientRouter.navigate
        let href = ambientRouter.href(forPath: path)
        var attributes: [Attribute] = [
            .href(href),
            .refBinding(AnyRefBinding(linkRef)),
        ]
        // The current page's link gets the web's standard "you are here":
        // aria-current="page" (an a11y signal AND a free styling hook,
        // `a[aria-current="page"]`) plus a stable class for selector-averse
        // stylesheets. Emitted only when active so inactive links stay
        // attribute-clean.
        if activeMatch.isActive(linkPath: path, currentPath: ambientRouter.path) {
            attributes.append(.attr("aria-current", "page"))
            attributes.append(.attr("class", "sw-link-active"))
        }
        switch content {
        case .label(let text):
            return element("a", attributes: attributes, children: [.text(text)])
        case .children(let nodes):
            return element("a", attributes: attributes, children: nodes)
        }
    }

    public func onAppear() {
        // Only build the JSClosure when the ref actually bound to a DOM
        // element. Besides not allocating a closure nothing will attach,
        // this is what makes Link HOST-RENDERABLE: under TestRenderer the
        // ref never binds, and constructing a JSClosure with no JS runtime
        // aborts the process (canImport(JavaScriptKit) is true on host —
        // the wall gates compilability, not runtime availability).
        guard let el = linkRef.wrappedValue else { return }
        let navigate = capturedNavigate ?? { _ in }
        let targetPath = path
        let closure = JSClosure { args -> JSValue in
            if let event = args.first?.object { _ = event.preventDefault!() }
            navigate(targetPath)
            return .undefined
        }
        _ = el.addEventListener!("click", closure)
        clickClosure = closure
    }

    public func onDisappear() {
        // removeEventListener stops the callback from firing; release()
        // detaches it. Both matter: detaching the click listener is what lets
        // the WeakRefs build GC-collect the closure once the field is dropped,
        // so skipping it leaked one closure per Link mount/unmount cycle (per
        // route change). `releaseIfNeeded()` additionally frees it on the
        // legacy non-WeakRefs build.
        if let closure = clickClosure {
            if let el = linkRef.wrappedValue {
                _ = el.removeEventListener!("click", closure)
            }
            closure.releaseIfNeeded()
        }
        clickClosure = nil
    }
}
#endif
