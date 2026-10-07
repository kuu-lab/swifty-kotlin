import Foundation
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeNetworkTests {
    private final class HTTPTestServer {
        private static let serverStartupTimeout: TimeInterval = 5
        private static let serverShutdownTimeout: TimeInterval = 5
        private static let serverShutdownPollInterval: TimeInterval = 0.05
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let scriptURL: URL
        let directoryURL: URL
        let port: Int

        init() throws {
            directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            scriptURL = directoryURL.appendingPathComponent("server.py")
            try serverScript.write(to: scriptURL, atomically: true, encoding: .utf8)

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "-u", scriptURL.path]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            try process.run()
            port = try Self.readPort(from: stdoutPipe.fileHandleForReading, process: process)
        }

        deinit {
            stop()
        }

        func stop() {
            if process.isRunning {
                process.terminate()
                let deadline = Date().addingTimeInterval(Self.serverShutdownTimeout)
                while process.isRunning, Date() < deadline {
                    Thread.sleep(forTimeInterval: Self.serverShutdownPollInterval)
                }
                if process.isRunning {
                    process.interrupt()
                    let interruptDeadline = Date().addingTimeInterval(Self.serverShutdownTimeout)
                    while process.isRunning, Date() < interruptDeadline {
                        Thread.sleep(forTimeInterval: Self.serverShutdownPollInterval)
                    }
                    if process.isRunning {
                        // Note: There's a race condition between this check and the kill() call where the process
                        // could exit and the PID could be reused. This is a fundamental limitation of the kill() API.
                        let killResult = kill(process.processIdentifier, SIGKILL)
                        if killResult != 0 && errno != ESRCH {
                            // kill() failed with error other than ESRCH (no such process)
                            // ESRCH is expected if process exited between isRunning check and kill call
                            // Other errors are unusual but we continue anyway
                        }
                        let sigkillDeadline = Date().addingTimeInterval(1.0)
                        while process.isRunning, Date() < sigkillDeadline {
                            Thread.sleep(forTimeInterval: Self.serverShutdownPollInterval)
                        }
                    }
                }
            }
            try? FileManager.default.removeItem(at: directoryURL)
        }

        private static func readPort(from handle: FileHandle, process: Process) throws -> Int {
            var bytes = Data()
            let deadline = Date().addingTimeInterval(serverStartupTimeout)
            while true {
                if Date() >= deadline {
                    throw NSError(domain: "RuntimeNetworkTests", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Timed out waiting for HTTP test server port"
                    ])
                }
                if !process.isRunning, bytes.isEmpty {
                    throw NSError(domain: "RuntimeNetworkTests", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "HTTP test server exited before reporting a port"
                    ])
                }
                let chunk = try handle.read(upToCount: 1) ?? Data()
                if chunk.isEmpty { break }
                if chunk[chunk.startIndex] == 10 { break }
                bytes.append(chunk)
            }
            guard let text = String(data: bytes, encoding: .utf8),
                  let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                throw NSError(domain: "RuntimeNetworkTests", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to read HTTP test server port"
                ])
            }
            return port
        }

        private let serverScript = """
import http.server
import socketserver
import sys

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/get")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/redirect-headers":
            self.send_response(302)
            self.send_header("Location", "/headers")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path.startswith("/redirect-port-"):
            target_port = self.path.rsplit("-", 1)[1]
            self.send_response(302)
            self.send_header("Location", f"http://127.0.0.1:{target_port}/headers")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/redirect-to-exact":
            self.send_response(302)
            self.send_header("Location", "/exact")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/redirect-to-huge":
            self.send_response(302)
            self.send_header("Location", "/huge-content-length")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/redirect-to-chunked-oversize":
            self.send_response(302)
            self.send_header("Location", "/chunked-oversize")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/headers":
            lines = sorted(f"{name.lower()}: {value}" for name, value in self.headers.items())
            body = "\\n".join(lines).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == "/exact":
            body = b"A" * 100
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == "/huge-content-length":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", "1073741824")
            self.end_headers()
            try:
                self.wfile.write(b"huge-payload-prefix")
                self.wfile.flush()
            except Exception:
                pass
            return
        if self.path == "/chunked-oversize":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            chunk = b"X" * 64
            chunk_line = f"{len(chunk):X}\\r\\n".encode("ascii") + chunk + b"\\r\\n"
            try:
                for _ in range(5):
                    self.wfile.write(chunk_line)
                    self.wfile.flush()
                self.wfile.write(b"0\\r\\n\\r\\n")
                self.wfile.flush()
            except Exception:
                pass
            return
        header = self.headers.get("X-Test", "")
        body = f"GET:{header}".encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("X-Echo", header)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        payload = self.rfile.read(length).decode("utf-8")
        body = f"POST:{payload}".encode("utf-8")
        self.send_response(201)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("X-Method", "POST")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return

class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True

with ThreadedTCPServer(("127.0.0.1", 0), Handler) as httpd:
    print(httpd.server_address[1], flush=True)
    httpd.serve_forever()
"""
    }

    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func stringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func listStrings(_ raw: Int) -> [String] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let list = tryCast(ptr, to: RuntimeListBox.self)
        else {
            return []
        }
        return list.elements.map(stringValue)
    }

    private func mapStringsToLists(_ raw: Int) -> [String: [String]] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let map = tryCast(ptr, to: RuntimeMapBox.self)
        else {
            return [:]
        }
        var result: [String: [String]] = [:]
        for (index, keyRaw) in map.keys.enumerated() where index < map.values.count {
            result[stringValue(keyRaw)] = listStrings(map.values[index])
        }
        return result
    }

    /// Reads one `name: value` line from the test server's /headers echo body.
    private func echoedHeader(_ body: String, name: String) -> String? {
        for line in body.split(separator: "\n") {
            let key = name.lowercased() + ":"
            if line.lowercased().hasPrefix(key) {
                return String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    @Test func httpClientSupportsGetAndPost() throws {
        let server = try HTTPTestServer()
        defer { server.stop() }

        var thrown = 0
        let clientRaw = kk_http_client_newHttpClient()
        let responseHandlerRaw = kk_http_body_handlers_ofString(0)

        let getURI = runtimeNetworkURI(from: runtimeString("http://127.0.0.1:\(server.port)/get"), &thrown)
        #expect(thrown == 0)
        let getBuilderRaw = kk_http_request_newBuilder_uri(getURI)
        _ = kk_http_request_builder_header(getBuilderRaw, runtimeString("X-Test"), runtimeString("alpha"))
        _ = kk_http_request_builder_GET(getBuilderRaw)
        let getRequestRaw = kk_http_request_builder_build(getBuilderRaw, &thrown)
        #expect(thrown == 0)

        let getResponseRaw = kk_http_client_send(clientRaw, getRequestRaw, responseHandlerRaw, &thrown)
        #expect(thrown == 0)
        #expect(kk_http_response_statusCode(getResponseRaw) == 200)
        #expect(stringValue(kk_http_response_body(getResponseRaw)) == "GET:alpha")

        let getHeadersRaw = kk_http_response_headers(getResponseRaw)
        #expect(stringValue(kk_http_headers_firstValue(getHeadersRaw, runtimeString("X-Echo"))) == "alpha")
        let getHeaderMap = mapStringsToLists(kk_http_headers_map(getHeadersRaw))
        #expect(getHeaderMap["X-Echo"]?.first == "alpha")

        let postURI = runtimeNetworkURI(from: runtimeString("http://127.0.0.1:\(server.port)/post"), &thrown)
        #expect(thrown == 0)
        let postBuilderRaw = kk_http_request_newBuilder()
        _ = kk_http_request_builder_uri(postBuilderRaw, postURI)
        _ = kk_http_request_builder_header(postBuilderRaw, runtimeString("Content-Type"), runtimeString("text/plain"))
        let publisherRaw = kk_http_body_publishers_ofString(0, runtimeString("payload"))
        _ = kk_http_request_builder_POST(postBuilderRaw, publisherRaw)
        let postRequestRaw = kk_http_request_builder_build(postBuilderRaw, &thrown)
        #expect(thrown == 0)

        let postResponseRaw = kk_http_client_send(clientRaw, postRequestRaw, responseHandlerRaw, &thrown)
        #expect(thrown == 0)
        #expect(kk_http_response_statusCode(postResponseRaw) == 201)
        #expect(stringValue(kk_http_response_body(postResponseRaw)) == "POST:payload")
        let postHeadersRaw = kk_http_response_headers(postResponseRaw)
        #expect(stringValue(kk_http_headers_firstValue(postHeadersRaw, runtimeString("X-Method"))) == "POST")
    }

    @Test func httpClientHonorsFollowRedirectsDisabled() throws {
        let server = try HTTPTestServer()
        defer { server.stop() }

        var thrown = 0
        let responseHandlerRaw = kk_http_body_handlers_ofString(0)
        let redirectURI = runtimeNetworkURI(from: runtimeString("http://127.0.0.1:\(server.port)/redirect"), &thrown)
        #expect(thrown == 0)

        let disabledClientRaw = kk_http_client_newHttpClient()
        _ = kk_http_client_setFollowRedirects(disabledClientRaw, 0)
        let disabledBuilderRaw = kk_http_request_newBuilder_uri(redirectURI)
        _ = kk_http_request_builder_GET(disabledBuilderRaw)
        let disabledRequestRaw = kk_http_request_builder_build(disabledBuilderRaw, &thrown)
        #expect(thrown == 0)

        let disabledResponseRaw = kk_http_client_send(disabledClientRaw, disabledRequestRaw, responseHandlerRaw, &thrown)
        #expect(thrown == 0)
        #expect(kk_http_response_statusCode(disabledResponseRaw) == 302)

        let defaultClientRaw = kk_http_client_newHttpClient()
        let defaultBuilderRaw = kk_http_request_newBuilder_uri(redirectURI)
        _ = kk_http_request_builder_GET(defaultBuilderRaw)
        let defaultRequestRaw = kk_http_request_builder_build(defaultBuilderRaw, &thrown)
        #expect(thrown == 0)

        let defaultResponseRaw = kk_http_client_send(defaultClientRaw, defaultRequestRaw, responseHandlerRaw, &thrown)
        #expect(thrown == 0)
        #expect(kk_http_response_statusCode(defaultResponseRaw) == 200)
        #expect(stringValue(kk_http_response_body(defaultResponseRaw)) == "GET:")
    }

    @Test func crossOriginRedirectDropsCallerSuppliedHeaders() throws {
        let redirectServer = try HTTPTestServer()
        defer { redirectServer.stop() }
        let targetServer = try HTTPTestServer()
        defer { targetServer.stop() }

        var thrown = 0
        let clientRaw = kk_http_client_newHttpClient()
        _ = kk_http_client_setBearerToken(clientRaw, runtimeString("client-token"))
        let responseHandlerRaw = kk_http_body_handlers_ofString(0)

        let uri = runtimeNetworkURI(
            from: runtimeString("http://127.0.0.1:\(redirectServer.port)/redirect-port-\(targetServer.port)"),
            &thrown
        )
        #expect(thrown == 0)
        let builderRaw = kk_http_request_newBuilder_uri(uri)
        for (name, value) in [
            ("Cookie", "session=secret"),
            ("Proxy-Authorization", "Basic cHJveHk="),
            ("X-API-Key", "secret-api-key"),
            ("X-Signature", "deadbeef"),
            ("X-Test", "custom"),
            ("Accept", "text/plain"),
        ] {
            _ = kk_http_request_builder_header(builderRaw, runtimeString(name), runtimeString(value))
        }
        _ = kk_http_request_builder_GET(builderRaw)
        let requestRaw = kk_http_request_builder_build(builderRaw, &thrown)
        #expect(thrown == 0)

        let responseRaw = kk_http_client_send(clientRaw, requestRaw, responseHandlerRaw, &thrown)
        #expect(thrown == 0)
        #expect(kk_http_response_statusCode(responseRaw) == 200)
        let echoed = stringValue(kk_http_response_body(responseRaw))
        for name in ["authorization", "cookie", "proxy-authorization", "x-api-key", "x-signature", "x-test"] {
            #expect(echoedHeader(echoed, name: name) == nil, "\(name) leaked across the cross-origin redirect")
        }
        #expect(echoedHeader(echoed, name: "accept") == "text/plain")
    }

    @Test func sameOriginRedirectRetainsCallerSuppliedHeaders() throws {
        let server = try HTTPTestServer()
        defer { server.stop() }

        var thrown = 0
        let clientRaw = kk_http_client_newHttpClient()
        let responseHandlerRaw = kk_http_body_handlers_ofString(0)

        let uri = runtimeNetworkURI(
            from: runtimeString("http://127.0.0.1:\(server.port)/redirect-headers"),
            &thrown
        )
        #expect(thrown == 0)
        let builderRaw = kk_http_request_newBuilder_uri(uri)
        _ = kk_http_request_builder_header(builderRaw, runtimeString("Authorization"), runtimeString("Bearer secret"))
        _ = kk_http_request_builder_header(builderRaw, runtimeString("X-API-Key"), runtimeString("secret-api-key"))
        _ = kk_http_request_builder_GET(builderRaw)
        let requestRaw = kk_http_request_builder_build(builderRaw, &thrown)
        #expect(thrown == 0)

        let responseRaw = kk_http_client_send(clientRaw, requestRaw, responseHandlerRaw, &thrown)
        #expect(thrown == 0)
        #expect(kk_http_response_statusCode(responseRaw) == 200)
        let echoed = stringValue(kk_http_response_body(responseRaw))
        #expect(echoedHeader(echoed, name: "authorization") == "Bearer secret")
        #expect(echoedHeader(echoed, name: "x-api-key") == "secret-api-key")
    }

    @Test func trustedRedirectOriginRetainsCallerSuppliedHeaders() throws {
        let redirectServer = try HTTPTestServer()
        defer { redirectServer.stop() }
        let targetServer = try HTTPTestServer()
        defer { targetServer.stop() }

        var thrown = 0
        let clientRaw = kk_http_client_newHttpClient()
        _ = kk_http_client_addTrustedRedirectOrigin(
            clientRaw,
            runtimeString("http://127.0.0.1:\(targetServer.port)")
        )
        let responseHandlerRaw = kk_http_body_handlers_ofString(0)

        let uri = runtimeNetworkURI(
            from: runtimeString("http://127.0.0.1:\(redirectServer.port)/redirect-port-\(targetServer.port)"),
            &thrown
        )
        #expect(thrown == 0)
        let builderRaw = kk_http_request_newBuilder_uri(uri)
        _ = kk_http_request_builder_header(builderRaw, runtimeString("Authorization"), runtimeString("Bearer secret"))
        _ = kk_http_request_builder_header(builderRaw, runtimeString("X-API-Key"), runtimeString("secret-api-key"))
        _ = kk_http_request_builder_GET(builderRaw)
        let requestRaw = kk_http_request_builder_build(builderRaw, &thrown)
        #expect(thrown == 0)

        let responseRaw = kk_http_client_send(clientRaw, requestRaw, responseHandlerRaw, &thrown)
        #expect(thrown == 0)
        #expect(kk_http_response_statusCode(responseRaw) == 200)
        let echoed = stringValue(kk_http_response_body(responseRaw))
        #expect(echoedHeader(echoed, name: "authorization") == "Bearer secret")
        #expect(echoedHeader(echoed, name: "x-api-key") == "secret-api-key")
    }

    @Test func httpRequestBuildThrowsWithoutURI() {
        var thrown = 0
        let builderRaw = kk_http_request_newBuilder()
        let requestRaw = kk_http_request_builder_build(builderRaw, &thrown)
        #expect(requestRaw == 0)
        #expect(thrown != 0)
    }

    @Test func httpClientAcceptsExactLimitResponse() throws {
        let server = try HTTPTestServer()
        defer { server.stop() }

        var thrown = 0
        let clientRaw = kk_http_client_newHttpClient()
        _ = kk_http_client_setMaxResponseBodyBytes(clientRaw, 100)
        let responseHandlerRaw = kk_http_body_handlers_ofString(0)

        let uri = runtimeNetworkURI(from: runtimeString("http://127.0.0.1:\(server.port)/exact"), &thrown)
        #expect(thrown == 0)
        let builderRaw = kk_http_request_newBuilder_uri(uri)
        _ = kk_http_request_builder_GET(builderRaw)
        let requestRaw = kk_http_request_builder_build(builderRaw, &thrown)
        #expect(thrown == 0)

        let responseRaw = kk_http_client_send(clientRaw, requestRaw, responseHandlerRaw, &thrown)
        #expect(thrown == 0)
        #expect(kk_http_response_statusCode(responseRaw) == 200)
        let body = stringValue(kk_http_response_body(responseRaw))
        #expect(body.utf8.count == 100)
        #expect(body == String(repeating: "A", count: 100))
    }

    @Test func httpClientRejectsExcessiveContentLengthBeforeDownload() throws {
        let server = try HTTPTestServer()
        defer { server.stop() }

        var thrown = 0
        let clientRaw = kk_http_client_newHttpClient()
        _ = kk_http_client_setMaxResponseBodyBytes(clientRaw, 100)
        let responseHandlerRaw = kk_http_body_handlers_ofString(0)

        let uri = runtimeNetworkURI(from: runtimeString("http://127.0.0.1:\(server.port)/huge-content-length"), &thrown)
        #expect(thrown == 0)
        let builderRaw = kk_http_request_newBuilder_uri(uri)
        _ = kk_http_request_builder_GET(builderRaw)
        let requestRaw = kk_http_request_builder_build(builderRaw, &thrown)
        #expect(thrown == 0)

        let responseRaw = kk_http_client_send(clientRaw, requestRaw, responseHandlerRaw, &thrown)
        #expect(responseRaw == 0)
        #expect(thrown != 0)
    }

    @Test func httpClientCancelsChunkedResponseExceedingLimit() throws {
        let server = try HTTPTestServer()
        defer { server.stop() }

        var thrown = 0
        let clientRaw = kk_http_client_newHttpClient()
        _ = kk_http_client_setMaxResponseBodyBytes(clientRaw, 50)
        let responseHandlerRaw = kk_http_body_handlers_ofString(0)

        let uri = runtimeNetworkURI(from: runtimeString("http://127.0.0.1:\(server.port)/chunked-oversize"), &thrown)
        #expect(thrown == 0)
        let builderRaw = kk_http_request_newBuilder_uri(uri)
        _ = kk_http_request_builder_GET(builderRaw)
        let requestRaw = kk_http_request_builder_build(builderRaw, &thrown)
        #expect(thrown == 0)

        let responseRaw = kk_http_client_send(clientRaw, requestRaw, responseHandlerRaw, &thrown)
        #expect(responseRaw == 0)
        #expect(thrown != 0)
    }

    @Test func httpClientMaintainsLimitAcrossRedirects() throws {
        let server = try HTTPTestServer()
        defer { server.stop() }

        var thrown = 0
        let clientRaw = kk_http_client_newHttpClient()
        _ = kk_http_client_setMaxResponseBodyBytes(clientRaw, 100)
        let responseHandlerRaw = kk_http_body_handlers_ofString(0)

        // 1. Redirect to exact limit should succeed
        let exactRedirectURI = runtimeNetworkURI(from: runtimeString("http://127.0.0.1:\(server.port)/redirect-to-exact"), &thrown)
        #expect(thrown == 0)
        let exactBuilderRaw = kk_http_request_newBuilder_uri(exactRedirectURI)
        _ = kk_http_request_builder_GET(exactBuilderRaw)
        let exactRequestRaw = kk_http_request_builder_build(exactBuilderRaw, &thrown)
        #expect(thrown == 0)

        let exactResponseRaw = kk_http_client_send(clientRaw, exactRequestRaw, responseHandlerRaw, &thrown)
        #expect(thrown == 0)
        #expect(kk_http_response_statusCode(exactResponseRaw) == 200)
        let exactBody = stringValue(kk_http_response_body(exactResponseRaw))
        #expect(exactBody.utf8.count == 100)

        // 2. Redirect to huge Content-Length should be rejected
        let hugeRedirectURI = runtimeNetworkURI(from: runtimeString("http://127.0.0.1:\(server.port)/redirect-to-huge"), &thrown)
        #expect(thrown == 0)
        let hugeBuilderRaw = kk_http_request_newBuilder_uri(hugeRedirectURI)
        _ = kk_http_request_builder_GET(hugeBuilderRaw)
        let hugeRequestRaw = kk_http_request_builder_build(hugeBuilderRaw, &thrown)
        #expect(thrown == 0)

        let hugeResponseRaw = kk_http_client_send(clientRaw, hugeRequestRaw, responseHandlerRaw, &thrown)
        #expect(hugeResponseRaw == 0)
        #expect(thrown != 0)

        // 3. Redirect to chunked oversize should be canceled
        let chunkedRedirectURI = runtimeNetworkURI(from: runtimeString("http://127.0.0.1:\(server.port)/redirect-to-chunked-oversize"), &thrown)
        #expect(thrown == 0)
        let chunkedBuilderRaw = kk_http_request_newBuilder_uri(chunkedRedirectURI)
        _ = kk_http_request_builder_GET(chunkedBuilderRaw)
        let chunkedRequestRaw = kk_http_request_builder_build(chunkedBuilderRaw, &thrown)
        #expect(thrown == 0)

        _ = kk_http_client_setMaxResponseBodyBytes(clientRaw, 50)
        let chunkedResponseRaw = kk_http_client_send(clientRaw, chunkedRequestRaw, responseHandlerRaw, &thrown)
        #expect(chunkedResponseRaw == 0)
        #expect(thrown != 0)
    }

    @Test func httpClientConfigurableLimitUpdatesDynamically() throws {
        let server = try HTTPTestServer()
        defer { server.stop() }

        var thrown = 0
        let clientRaw = kk_http_client_newHttpClient()
        let responseHandlerRaw = kk_http_body_handlers_ofString(0)
        let uri = runtimeNetworkURI(from: runtimeString("http://127.0.0.1:\(server.port)/exact"), &thrown)
        #expect(thrown == 0)
        let builderRaw = kk_http_request_newBuilder_uri(uri)
        _ = kk_http_request_builder_GET(builderRaw)
        let requestRaw = kk_http_request_builder_build(builderRaw, &thrown)
        #expect(thrown == 0)

        // Default limit (10MB) accepts 100 bytes
        let res1 = kk_http_client_send(clientRaw, requestRaw, responseHandlerRaw, &thrown)
        #expect(thrown == 0)
        #expect(kk_http_response_statusCode(res1) == 200)

        // Tighten limit to 50 bytes -> rejects 100-byte response
        _ = kk_http_client_setMaxResponseBodyBytes(clientRaw, 50)
        let res2 = kk_http_client_send(clientRaw, requestRaw, responseHandlerRaw, &thrown)
        #expect(res2 == 0)
        #expect(thrown != 0)

        // Relax limit to 200 bytes -> accepts 100-byte response again
        _ = kk_http_client_setMaxResponseBodyBytes(clientRaw, 200)
        let res3 = kk_http_client_send(clientRaw, requestRaw, responseHandlerRaw, &thrown)
        #expect(thrown == 0)
        #expect(kk_http_response_statusCode(res3) == 200)
    }
}
