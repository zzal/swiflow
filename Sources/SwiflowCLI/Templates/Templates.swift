// Sources/SwiflowCLI/Templates/Templates.swift
//
// Templates that `swiflow init` writes to the new project directory.
// These are plain String constants — no SwiftPM resources — so they
// participate naturally in `swift test` and don't require Bundle access.
//
// Variable substitution is dumb `replacingOccurrences`. Phase 2b has two
// variables: {{NAME}} (project name) and {{SWIFLOW_SOURCE}} (path or URL
// the generated Package.swift uses to depend on Swiflow). If we ever need
// a third, consider promoting to a real templating helper.

import Foundation

enum Templates {

    // MARK: - Public rendering API

    static func packageSwift(name: String, swiflowSource: String) -> String {
        return rawPackageSwift
            .replacingOccurrences(of: "{{NAME}}", with: name)
            .replacingOccurrences(of: "{{SWIFLOW_SOURCE}}", with: swiflowSource)
    }

    static func appSwift(name: String) -> String {
        return rawAppSwift
            .replacingOccurrences(of: "{{NAME}}", with: name)
    }

    static func indexHTML(name: String) -> String {
        return rawIndexHTML
            .replacingOccurrences(of: "{{NAME}}", with: name)
    }

    static func gitignore() -> String {
        return rawGitignore
    }

    static func readme(name: String) -> String {
        return rawReadme
            .replacingOccurrences(of: "{{NAME}}", with: name)
    }

    // MARK: - Raw template strings
    //
    // These are byte-identical to the current examples/HelloWorld/ files,
    // with `HelloWorld` replaced by `{{NAME}}` and `../..` by
    // `{{SWIFLOW_SOURCE}}`. The TemplatesTests assert the round-trip.
    //
    // LOAD-BEARING FORMATTING: each constant ends with a blank line before
    // the closing `"""`. Swift strips ONE trailing newline from indented
    // multi-line literals, but the on-disk example files end with `\n`, so
    // the source needs an extra newline that Swift then strips — leaving
    // one `\n` in the rendered string. Do NOT delete those blank lines.
    // (See DriverEmbedder.swift for the same trick with more explanation.)

    private static let rawPackageSwift: String = """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "{{NAME}}",
            // Required because this app links SwiflowWeb, which transitively pulls
            // Hummingbird 2.x (macOS 14+). Without this floor, `swift build` fails
            // with "executable 'App' requires macos 10.13, but depends on the
            // product 'SwiflowWeb' which requires macos 14.0".
            platforms: [.macOS(.v14)],
            products: [
                .executable(name: "App", targets: ["App"]),
            ],
            dependencies: [
                // Local path back to the parent Swiflow package.
                .package(path: "{{SWIFLOW_SOURCE}}"),
                // JavaScriptKit is declared as a direct dependency so SwiftPM
                // exposes the `swift package js` (PackageToJS) plugin to this
                // package. Without it, the plugin only surfaces on the parent
                // package and can't target this example's executable.
                .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
            ],
            targets: [
                .executableTarget(
                    name: "App",
                    dependencies: [
                        .product(name: "SwiflowWeb", package: "Swiflow"),
                    ],
                    path: "Sources/App"
                ),
            ]
        )

        """

    private static let rawAppSwift: String = #"""
        // Sources/App/App.swift
        import Swiflow
        import SwiflowWeb
        import JavaScriptKit

        /// Counter — the Phase 7 demo component.
        ///
        /// `final class` (not `struct`) is required: @State reactivity wires the
        /// owner via Mirror after init, which needs reference semantics. See
        /// Sources/Swiflow/Reactivity/Component.swift for the rationale. The
        /// `final` keyword is optional but matches the framework's expectation
        /// that Components aren't subclassed.
        ///
        /// **Hot reload preserves `@State`.** When you save this file while
        /// `swiflow dev` is running, the runtime captures the current values
        /// of `count`, `greeting`, and `celebrate`, re-imports the rebuilt
        /// WASM, and restores them into the new module — so editing a
        /// rendering tweak (e.g. changing the button label) does NOT reset
        /// the counter back to zero. State preservation matches by
        /// (component type name, @State field name); rename `Counter` and
        /// the subtree starts fresh, which is the expected escape hatch
        /// when you want a clean slate.
        final class Counter: Component {
            @State var count: Int = 0
            @State var greeting: String = "Swiflow"
            @State var celebrate: Bool = false
            let greetingInput = Ref<JSObject>()

            var body: VNode {
                div(.class("container")) {
                    h1("Hello, \(greeting)!\(celebrate ? " \u{1F389}" : "")")
                    p("Count: \(count)")
                    button("Increment", .on(.click) { self.count += 1 })

                    div(.class("greeting-row")) {
                        label("Greeting", .attr("for", "g"))
                        input(.id("g"), .value($greeting), .ref(greetingInput))
                    }

                    label(.class("checkbox-row")) {
                        input(.attr("type", "checkbox"), .checked($celebrate))
                        VNode.text(" Celebrate")
                    }
                }
            }

            func onAppear() {
                _ = greetingInput.wrappedValue?.focus.function?()
            }
        }

        @main
        struct App {
            @MainActor
            static func main() {
                Swiflow.render(into: "#app") { Counter() }
            }
        }

        """#

    private static let rawIndexHTML: String = """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <title>{{NAME}}</title>
            <style>
              body { font-family: -apple-system, system-ui, sans-serif; padding: 2rem; }
              .container { max-width: 480px; }
              button { padding: 0.4rem 0.9rem; font-size: 1rem; cursor: pointer; }
              .greeting-row { display: flex; gap: 0.5rem; align-items: center; margin-top: 1rem; }
              .greeting-row input { flex: 1; padding: 0.3rem 0.5rem; }
              .checkbox-row { display: flex; gap: 0.5rem; align-items: center; margin-top: 0.5rem; }
            </style>
          </head>
          <body>
            <div id="app"></div>

            <!-- Load the Swiflow driver BEFORE the WASM bootstrap so
                 `window.swiflow` exists when App.main calls `Swiflow.render`. -->
            <script src="swiflow-driver.js"></script>

            <!--
              JavaScriptKit 0.53's PackageToJS plugin (`swift package js`) emits a
              ready-to-import ES module at .build/plugins/PackageToJS/outputs/Package/
              that handles WASI + Swift runtime initialization. Build first:

                  swift package --swift-sdk swift-6.3-RELEASE_wasm js -c release

              then open index.html via a static server rooted at this directory
              (so the relative .build path resolves).
            -->
            <script type="module">
              import { init } from "./.build/plugins/PackageToJS/outputs/Package/index.js";
              await init();
            </script>
          </body>
        </html>

        """

    private static let rawGitignore: String = """
        .DS_Store
        .build/
        .swiftpm/

        """

    private static let rawReadme: String = """
        # {{NAME}}

        A Swiflow project — Swift-to-WebAssembly with a Vite-inspired dev loop.

        ## Build

        ```bash
        swiflow build
        ```

        This wraps `swift package js --use-cdn --product App -c release` after
        probing for an installed WASM SDK. The output lands at
        `.build/plugins/PackageToJS/outputs/Package/`.

        ## Serve

        Phase 2b doesn't ship a dev server yet (Phase 2c will). Any static HTTP
        server works:

        ```bash
        python3 -m http.server 3000
        ```

        Then open <http://localhost:3000>.

        ## What you should see

        - A heading: **Hello, Swiflow!**
        - A paragraph: **Count: 0**
        - A button: **Increment** that increments the count on each click.

        """
}
