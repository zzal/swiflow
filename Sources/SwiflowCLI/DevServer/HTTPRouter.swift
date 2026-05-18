// Sources/SwiflowCLI/DevServer/HTTPRouter.swift
//
// Builds a Hummingbird Router that:
//   - serves the project root statically (index.html, swiflow-driver.js,
//     the built .wasm + index.js, plus anything else the user puts there)
//   - rewrites HTML responses through DevModeInjection so the JS driver's
//     reload-WS branch activates
//
// Kept as a free `build(projectRoot:)` function (no class) so tests can
// construct the router directly and feed it into `Application` without
// a DevServer wrapper.

import Foundation
import Hummingbird
import NIOCore

enum HTTPRouter {
    /// Construct the dev-server router rooted at `projectRoot`. The
    /// router serves files under `projectRoot/` plus a synthetic `/`
    /// route that resolves to `index.html`. HTML responses pass through
    /// DevModeInjection.
    static func build(projectRoot: URL) -> Router<BasicRequestContext> {
        let router = Router()

        // GET / → index.html (with injection)
        router.get("/") { _, context in
            try await serveFile(at: projectRoot.appendingPathComponent("index.html"), context: context)
        }

        // GET /:path — anything else under projectRoot
        router.get("/**") { _, context in
            let rel = context.parameters.getCatchAll().joined(separator: "/")
            guard !rel.isEmpty else {
                throw HTTPError(.notFound)
            }
            // Defence: refuse path-traversal attempts. A `..` segment
            // before resolution means the user is trying to escape root.
            guard !rel.split(separator: "/").contains("..") else {
                throw HTTPError(.forbidden)
            }
            return try await serveFile(at: projectRoot.appendingPathComponent(rel), context: context)
        }

        return router
    }

    /// Read `fileURL` from disk and wrap it in a `Response`. HTML files
    /// pass through DevModeInjection so the dev-mode global is set
    /// before the driver IIFE runs.
    private static func serveFile<Context: RequestContext>(at fileURL: URL, context: Context) async throws -> Response {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else {
            throw HTTPError(.notFound)
        }

        let data = try Data(contentsOf: fileURL)
        let contentType = mimeType(for: fileURL.pathExtension)

        let bodyData: Data
        if contentType.hasPrefix("text/html"), let html = String(data: data, encoding: .utf8) {
            bodyData = Data(DevModeInjection.injectDevSignal(into: html).utf8)
        } else {
            bodyData = data
        }

        var response = Response(
            status: .ok,
            headers: [.contentType: contentType],
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bodyData))
        )
        // Disable browser caching in dev so file-watcher reloads see fresh content.
        response.headers[.cacheControl] = "no-store"
        return response
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs":   return "application/javascript; charset=utf-8"
        case "css":         return "text/css; charset=utf-8"
        case "wasm":        return "application/wasm"
        case "json":        return "application/json; charset=utf-8"
        case "map":         return "application/json; charset=utf-8"
        case "svg":         return "image/svg+xml"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "ico":         return "image/x-icon"
        default:            return "application/octet-stream"
        }
    }
}
