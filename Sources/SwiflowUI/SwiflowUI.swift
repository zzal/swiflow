// Sources/SwiflowUI/SwiflowUI.swift
//
// SwiflowUI re-exports the Swiflow core so `import SwiflowUI` alone brings the
// framework surface every component signature already speaks — `VNode`,
// `@State` / `@Component`, `Binding`, `Attribute`, and the `@resultBuilder`
// DSL — with no separate `import Swiflow`. (You still `import SwiflowDOM` for the
// WASM renderer entry point, `Swiflow.render(into:)`.) Mirrors SwiflowDOM, which
// re-exports Swiflow the same way (see SwiflowDOM.swift).
@_exported import Swiflow
