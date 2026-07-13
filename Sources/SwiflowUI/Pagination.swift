// Sources/SwiflowUI/Pagination.swift
import Swiflow

/// A stateless pager: Previous/Next buttons flanking a "Page X of N" indicator, driven by
/// a 0-based `currentPage` and reporting changes through `onChange`.
///
///     Pagination(currentPage: page, pageCount: 5, onChange: { page = $0 })
///
/// Extracted verbatim from `DataTable`'s inline pager (same markup, same behavior) so any
/// paginated view — not just `DataTable` — can reach for it; `DataTable` itself now renders
/// this component instead of its own copy.
///
/// Previous is `inert` (project rule: `inert`, not `disabled`) when `currentPage <= 0`;
/// Next is `inert` when `currentPage >= pageCount - 1`. An inert button carries NO click
/// handler at all (matching every other disabled control in this library). The page
/// indicator displays 1-based (`"Page \(currentPage + 1) of \(pageCount)"`) over the
/// 0-based `currentPage` index used everywhere else.
///
/// Stateless free function; caller `Attribute...`/`.class` land on the `.sw-pagination`
/// root div, same convention as `ToggleButtonGroup`/`Breadcrumbs`.
@MainActor
public func Pagination(
    currentPage: Int,
    pageCount: Int,
    onChange: @escaping (Int) -> Void,
    _ attributes: Attribute...
) -> VNode {
    paginationBody(currentPage: currentPage, pageCount: pageCount, onChange: onChange, caller: attributes)
}

/// `Binding` overload: delegates to the core overload, writing the new page back to
/// `page` on change.
@MainActor
public func Pagination(
    page: Binding<Int>,
    pageCount: Int,
    _ attributes: Attribute...
) -> VNode {
    paginationBody(currentPage: page.get(), pageCount: pageCount, onChange: { page.set($0) }, caller: attributes)
}

/// The shared lowering both overloads call.
@MainActor
private func paginationBody(
    currentPage: Int,
    pageCount: Int,
    onChange: @escaping (Int) -> Void,
    caller: [Attribute]
) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-pagination", paginationSheet)

    func navBtn(_ label: String, _ target: Int, disabled: Bool) -> VNode {
        var attrs: [Attribute] = [.class("sw-pagination__btn"), .attr("type", "button"), .attr("aria-label", label)]
        if disabled { attrs.append(.attr("inert", true)) }     // project rule: inert, not disabled
        else { attrs.append(.on(.click) { onChange(target) }) }
        return element("button", attributes: attrs, children: [text(label)])
    }

    let (callerClasses, callerRest) = splitClasses(caller)
    let rootClass = (["sw-pagination"] + callerClasses).joined(separator: " ")

    return element("div", attributes: [.class(rootClass)] + callerRest, children: [
        navBtn("Previous", currentPage - 1, disabled: currentPage <= 0),
        element("span", attributes: [.class("sw-pagination__info")],
                children: [text("Page \(currentPage + 1) of \(pageCount)")]),
        navBtn("Next", currentPage + 1, disabled: currentPage >= pageCount - 1),
    ])
}

/// Token-driven pager chrome, lifted verbatim from `DataTable`'s old inline pager rules
/// (renamed general): a flex row right-aligned, muted page-info text, and unstyled
/// bordered buttons that dim + lose the pointer cursor while `[inert]`.
let paginationSheet: CSSSheet = css {
    raw("""
    .sw-pagination { display: flex; align-items: center; justify-content: flex-end; gap: var(--sw-space-sm); }
    .sw-pagination__info { color: var(--sw-text-muted); font-size: 0.875rem; }
    .sw-pagination__btn {
      all: unset; cursor: pointer; font: inherit;
      padding: var(--sw-space-xs) var(--sw-space-sm);
      border: 1px solid var(--sw-border); border-radius: var(--sw-radius);
      transition: box-shadow var(--sw-duration) var(--sw-ease);
    }
    .sw-pagination__btn[inert] { opacity: 0.5; cursor: default; }
    .sw-pagination__btn:focus-visible { outline: 2px solid transparent; box-shadow: var(--sw-focus-shadow); }
    """)
}
