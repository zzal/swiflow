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

        /// Counter — the Phase 12a styling/animation demo component.
        ///
        /// Showcases:
        /// - `static var scopedStyles: CSSSheet?` with `css { }` builder
        /// - `keyframes` enter animation scoped to the component
        /// - `Toast` child component with `exitAnimation` / `exitDuration`
        /// - `if showToast { embed { Toast(...) } }` conditional embedding
        ///
        /// Phase 7 features (two-way bindings, Ref) are preserved from prior work.
        final class Counter: Component {
            @State var count: Int = 0
            @State var greeting: String = "Swiflow"
            @State var celebrate: Bool = false
            @State var showToast: Bool = false
            @State var showSignIn: Bool = false
            let greetingInput = Ref<JSObject>()

            static var scopedStyles: CSSSheet? = css {
                keyframes("counter-in") {
                    from { opacity("0"); transform("translateY(-6px)") }
                    to   { opacity("1"); transform("translateY(0)") }
                }
                rule(".container") {
                    maxWidth("480px")
                    margin("2rem auto")
                    padding("2rem")
                    fontFamily("-apple-system, BlinkMacSystemFont, sans-serif")
                    animation("counter-in 0.3s ease forwards")
                }
                rule(".count") {
                    fontSize("1.5rem")
                    fontWeight("600")
                    color("#1a202c")
                }
                rule(".greeting-row") {
                    display("flex")
                    gap("0.5rem")
                    alignItems("center")
                    marginTop("1rem")
                }
                rule(".checkbox-row") {
                    display("flex")
                    gap("0.5rem")
                    alignItems("center")
                    marginTop("0.75rem")
                    cursor("pointer")
                }
            }

            var body: VNode {
                div(.class("container")) {
                    h1("Hello, \(greeting)!\(celebrate ? " \u{1F389}" : "")")
                    p("Count: \(count)", .class("count"))
                    button("Increment", .on(.click) { self.count += 1 })
                    button("Show toast", .on(.click) { self.showToast = true })

                    div(.class("greeting-row")) {
                        label("Greeting:", .attr("for", "g"))
                        input(.id("g"), .value($greeting), .ref(greetingInput))
                    }

                    label(.class("checkbox-row")) {
                        input(.attr("type", "checkbox"), .checked($celebrate))
                        VNode.text(" Celebrate")
                    }

                    if showToast {
                        embed { Toast(message: "Saved!", onDone: { self.showToast = false }) }
                    }

                    div(.style(name: "margin-top", value: "2rem"),
                        .style(name: "border-top", value: "1px solid #eee"),
                        .style(name: "padding-top", value: "1.5rem")) {
                        button(showSignIn ? "Hide Sign In" : "Show Sign In demo",
                               .on(.click) { self.showSignIn.toggle() })
                        if showSignIn {
                            embed { SignIn() }
                        }
                    }
                }
            }

            func onAppear() {
                if let el = greetingInput.wrappedValue { _ = el.focus!() }
            }
        }

        /// Toast — demonstrates `exitAnimation` and `exitDuration`.
        ///
        /// When the user clicks the toast (or the parent sets `showToast = false`),
        /// the framework plays the `toast-out` keyframe for `exitDuration` seconds
        /// before removing the DOM node — a smooth exit with zero JS glue.
        final class Toast: Component {
            let message: String
            let onDone: () -> Void

            init(message: String, onDone: @escaping () -> Void) {
                self.message = message
                self.onDone = onDone
            }

            static var scopedStyles: CSSSheet? = css {
                keyframes("toast-in") {
                    from { opacity("0"); transform("translateY(8px)") }
                    to   { opacity("1"); transform("translateY(0)") }
                }
                keyframes("toast-out") {
                    to { opacity("0"); transform("translateY(8px)") }
                }
                rule(".root") {
                    backgroundColor("#323232")
                    color("#fff")
                    padding("0.75rem 1.25rem")
                    borderRadius("8px")
                    marginTop("1rem")
                    animation("toast-in 0.2s ease forwards")
                    cursor("pointer")
                }
            }

            static var exitAnimation: String? = "toast-out 0.25s ease forwards"
            static var exitDuration: Double?  = 0.25

            var body: VNode {
                div(.class("root"), .on(.click) { self.onDone() }) {
                    VNode.text(message)
                }
            }
        }

        /// SignIn — Phase 12b form validation demo.
        ///
        /// Showcases:
        /// - `FormController` + `Field` + `Form` coordinator
        /// - Two-field form (email + password) with blur-triggered error messages
        /// - Submit disabled until `form.isValid`; `touchAll()` reveals all errors on early click
        /// - Reset button restores initial values
        final class SignIn: Component {
            @State var email    = ""
            @State var password = ""
            @State var ctrl     = FormController()
            @State var submitted = false

            var body: VNode {
                let em = Field("email",    $email,    $ctrl, .required(), .email)
                let pw = Field("password", $password, $ctrl, .required(), .minLength(8),
                               .custom("Must contain a number") { $0.contains { $0.isNumber } })
                let form = Form($ctrl) { em; pw }

                return div(.style(name: "max-width", value: "320px"),
                    .style(name: "margin", value: "1rem 0"),
                    .style(name: "font-family", value: "system-ui, sans-serif")) {

                    if submitted {
                        p("Signed in as \(email)!")
                        button("Sign out", .on(.click) {
                            self.submitted = false
                            self.email = ""
                            self.password = ""
                            self.ctrl = FormController()
                        })
                    } else {
                        h2("Sign In")

                        div(.style(name: "margin-bottom", value: "1rem")) {
                            label("Email")
                            input(.value($email),
                                  .style(name: "display", value: "block"),
                                  .style(name: "width", value: "100%"),
                                  .style(name: "margin-top", value: "4px"),
                                  .on(.blur) { em.markTouched() })
                            if em.touched, let err = em.error {
                                p(err,
                                  .style(name: "color", value: "red"),
                                  .style(name: "font-size", value: "0.85rem"))
                            }
                        }

                        div(.style(name: "margin-bottom", value: "1rem")) {
                            label("Password")
                            input(.value($password),
                                  .style(name: "display", value: "block"),
                                  .style(name: "width", value: "100%"),
                                  .style(name: "margin-top", value: "4px"),
                                  .on(.blur) { pw.markTouched() })
                            if pw.touched, let err = pw.error {
                                p(err,
                                  .style(name: "color", value: "red"),
                                  .style(name: "font-size", value: "0.85rem"))
                            }
                        }

                        button("Sign In",
                               .style(name: "margin-right", value: "0.5rem"),
                               .attr("disabled", !form.isValid),
                               .on(.click) {
                                   form.touchAll()
                                   guard form.isValid else { return }
                                   self.submitted = true
                               })
                        button("Reset", .on(.click) { form.reset() })
                    }
                }
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
