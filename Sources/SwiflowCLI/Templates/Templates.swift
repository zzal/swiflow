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
        // examples/{{NAME}}/Sources/App/App.swift
        import SwiflowWeb

        // Mutable counter shared with the click handler. Phase 3 will replace this
        // with `@State`; for Phase 2a the spec's Hello World uses an explicit
        // `Swiflow.rerender()` call so the bridge path is exercised end-to-end.
        //
        // `@MainActor` keeps Swift 6's strict-concurrency check happy: the browser
        // runs everything on a single thread, so pinning this to MainActor reflects
        // reality and silences `#MutableGlobalVariable`.
        @MainActor
        var count = 0

        @MainActor
        func view() -> VNode {
            div(.class("container")) {
                h1("Hello, Swiflow!")
                p("Count: \(count)")
                button(
                    "Increment",
                    // `MainActor.assumeIsolated` is safe here: the JS driver invokes
                    // every event listener synchronously on the only thread the WASM
                    // runtime owns, which the Swift runtime treats as the main actor.
                    // Using `Task { @MainActor in ... }` would defer the increment to
                    // a later event-loop turn and break the synchronous `rerender()`
                    // expectation.
                    .on("click", Swiflow.handlers.register { _ in
                        MainActor.assumeIsolated {
                            count += 1
                            Swiflow.rerender()
                        }
                    })
                )
            }
        }

        @main
        struct App {
            @MainActor
            static func main() {
                Swiflow.render(view, into: "#app")
            }
        }

        """#

    private static let rawIndexHTML: String = """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <title>Swiflow Hello World</title>
            <style>
              body { font-family: -apple-system, system-ui, sans-serif; padding: 2rem; }
              .container { max-width: 480px; }
              button { padding: 0.4rem 0.9rem; font-size: 1rem; cursor: pointer; }
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
