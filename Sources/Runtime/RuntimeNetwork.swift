import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let defaultMaxResponseBodyBytes: Int = {
    if let env = ProcessInfo.processInfo.environment["KSWIFTK_HTTP_MAX_RESPONSE_BODY_BYTES"],
       let limit = Int(env), limit >= 0 {
        return limit
    }
    return 10 * 1024 * 1024
}()

private struct StreamingUTF8Decoder {
    private var pending: [UInt8] = []
    private(set) var string: String = ""

    mutating func append(_ data: Data) {
        if data.isEmpty { return }
        let bytes: [UInt8]
        if pending.isEmpty {
            bytes = [UInt8](data)
        } else {
            bytes = pending + [UInt8](data)
            pending.removeAll(keepingCapacity: true)
        }

        var i = 0
        var lastValidEnd = 0
        let count = bytes.count

        while i < count {
            let b = bytes[i]
            let needed: Int
            if b & 0x80 == 0 {
                needed = 1
            } else if b & 0xE0 == 0xC0 {
                needed = 2
            } else if b & 0xF0 == 0xE0 {
                needed = 3
            } else if b & 0xF8 == 0xF0 {
                needed = 4
            } else {
                needed = 1
            }

            if i + needed <= count {
                i += needed
                lastValidEnd = i
            } else {
                pending = Array(bytes[i...])
                break
            }
        }

        if lastValidEnd > 0 {
            string += String(decoding: bytes[0..<lastValidEnd], as: UTF8.self)
        }
    }

    mutating func finish() {
        if !pending.isEmpty {
            string += String(decoding: pending, as: UTF8.self)
            pending.removeAll()
        }
    }
}

private final class RuntimeHTTPClientBox {
    private let lock = NSLock()
    private var connectTimeoutMillis: Int = 30_000
    private var readTimeoutMillis: Int = 30_000
    private var followRedirects = true
    private var defaultHeaders: [String: String] = [:]
    private var authHeader: String?
    private var trustedRedirectOrigins: Set<String> = []
    private var maxResponseBodyBytes: Int = defaultMaxResponseBodyBytes

    struct Snapshot {
        let connectTimeoutMillis: Int
        let readTimeoutMillis: Int
        let followRedirects: Bool
        let defaultHeaders: [String: String]
        let authHeader: String?
        let trustedRedirectOrigins: Set<String>
        let maxResponseBodyBytes: Int
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            connectTimeoutMillis: connectTimeoutMillis,
            readTimeoutMillis: readTimeoutMillis,
            followRedirects: followRedirects,
            defaultHeaders: defaultHeaders,
            authHeader: authHeader,
            trustedRedirectOrigins: trustedRedirectOrigins,
            maxResponseBodyBytes: maxResponseBodyBytes
        )
    }

    func setConnectTimeoutMillis(_ value: Int) {
        lock.lock()
        connectTimeoutMillis = max(0, value)
        lock.unlock()
    }

    func setReadTimeoutMillis(_ value: Int) {
        lock.lock()
        readTimeoutMillis = max(0, value)
        lock.unlock()
    }

    func setFollowRedirects(_ value: Bool) {
        lock.lock()
        followRedirects = value
        lock.unlock()
    }

    func setBearerToken(_ token: String) {
        lock.lock()
        authHeader = "Bearer \(token)"
        lock.unlock()
    }

    func addTrustedRedirectOrigin(_ originKey: String) {
        lock.lock()
        trustedRedirectOrigins.insert(originKey)
        lock.unlock()
    }

    func setMaxResponseBodyBytes(_ value: Int) {
        lock.lock()
        maxResponseBodyBytes = max(0, value)
        lock.unlock()
    }
}

final class RuntimeHttpRequestBuilderBox {
    var url: URL?
    var method: String
    var headers: [(String, String)]
    var body: Data?

    init(url: URL? = nil, method: String = "GET", headers: [(String, String)] = [], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

final class RuntimeHttpRequestBox {
    let url: URL
    let method: String
    let headers: [(String, String)]
    let body: Data?

    init(url: URL, method: String, headers: [(String, String)], body: Data?) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

final class RuntimeHttpBodyPublisherBox {
    let data: Data?

    init(data: Data?) {
        self.data = data
    }
}

final class RuntimeHttpBodyHandlerBox {
    let kind: String

    init(kind: String) {
        self.kind = kind
    }
}

final class RuntimeHttpResponseBox {
    let statusCode: Int
    let headers: [(String, [String])]
    let body: String
    let url: String
    let errorMessage: String?
    let timedOut: Bool

    init(
        statusCode: Int,
        headers: [(String, [String])],
        body: String,
        url: String = "",
        errorMessage: String? = nil,
        timedOut: Bool = false
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.url = url
        self.errorMessage = errorMessage
        self.timedOut = timedOut
    }

    var isSuccessful: Bool {
        errorMessage == nil && (200 ... 299).contains(statusCode)
    }
}

final class RuntimeHttpHeadersBox {
    let headers: [(String, [String])]

    init(headers: [(String, [String])]) {
        self.headers = headers
    }
}

/// Canonical origin key (scheme, host, effective port) shared by the
/// same-origin check and the trusted-redirect-origin list so both classify
/// origins identically.
private func runtimeOriginKey(_ url: URL?) -> String? {
    guard let url,
          let scheme = url.scheme?.lowercased(),
          let host = url.host?.lowercased()
    else {
        return nil
    }
    let port: Int?
    if let explicit = url.port {
        port = explicit
    } else {
        switch scheme {
        case "https": port = 443
        case "http": port = 80
        default: port = nil
        }
    }
    guard let port else { return "\(scheme)://\(host)" }
    return "\(scheme)://\(host):\(port)"
}

/// URLSession delegate that enforces a client's redirect policy, prevents
/// caller-supplied headers from leaking across origins on redirects, and
/// guards against memory exhaustion by enforcing body size limits.
private final class RuntimeHTTPSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Headers re-applied on an untrusted cross-origin redirect. They carry
    /// request semantics (representation metadata, content negotiation,
    /// caching, ranges) but no credentials or origin-identifying data, so
    /// forwarding them cannot leak secrets to another origin. Every other
    /// caller-supplied header — Authorization, Cookie, Proxy-Authorization,
    /// API keys, signing headers — is dropped deny-by-default.
    private static let crossOriginSafeRequestHeaders: Set<String> = [
        "accept", "accept-charset", "accept-encoding", "accept-language",
        "cache-control",
        "content-encoding", "content-language", "content-length", "content-location",
        "content-md5", "content-range", "content-type",
        "date", "dnt", "expect",
        "if-match", "if-modified-since", "if-none-match", "if-range", "if-unmodified-since",
        "max-forwards", "pragma", "range", "save-data", "sec-gpc",
        "te", "trailer", "upgrade", "upgrade-insecure-requests",
        "user-agent", "via", "warning", "x-requested-with",
    ]

    private let followRedirects: Bool
    private let trustedRedirectOrigins: Set<String>
    private let maxResponseBodyBytes: Int
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()

    private var decoder = StreamingUTF8Decoder()
    private var receivedByteCount: Int = 0
    private var sizeExceeded: Bool = false
    private var response: HTTPURLResponse?
    private var error: Error?
    private var responseBody: String = ""

    init(
        followRedirects: Bool,
        trustedRedirectOrigins: Set<String>,
        maxResponseBodyBytes: Int
    ) {
        self.followRedirects = followRedirects
        self.trustedRedirectOrigins = trustedRedirectOrigins
        self.maxResponseBodyBytes = maxResponseBodyBytes
    }

    func waitForResult() -> (response: HTTPURLResponse?, body: String, error: Error?) {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        return (response, responseBody, error)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard followRedirects else {
            // Stop the redirect: deliver the 3xx response to the caller instead
            // of following the Location header.
            completionHandler(nil)
            return
        }

        lock.lock()
        receivedByteCount = 0
        decoder = StreamingUTF8Decoder()
        sizeExceeded = false
        self.response = nil
        lock.unlock()

        var redirected = request
        if !RuntimeHTTPSessionDelegate.sameOrigin(task.originalRequest?.url, request.url)
            && !isTrustedRedirectTarget(request.url) {
            // Deny-by-default on a cross-origin redirect: keep only the safe
            // allowlist so credential-bearing or signing headers cannot leak
            // to a different origin.
            if let headerFields = redirected.allHTTPHeaderFields {
                for name in headerFields.keys
                where !RuntimeHTTPSessionDelegate.crossOriginSafeRequestHeaders.contains(name.lowercased()) {
                    redirected.setValue(nil, forHTTPHeaderField: name)
                }
            }
        }
        completionHandler(redirected)
    }

    private func isTrustedRedirectTarget(_ url: URL?) -> Bool {
        guard let key = runtimeOriginKey(url) else { return false }
        return trustedRedirectOrigins.contains(key)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }

        lock.lock()
        self.response = httpResponse

        var declaredLength: Int64 = httpResponse.expectedContentLength
        if let lengthHeader = httpResponse.allHeaderFields.first(where: {
            ($0.key as? String)?.caseInsensitiveCompare("Content-Length") == .orderedSame
        })?.value as? String, let parsed = Int64(lengthHeader.trimmingCharacters(in: .whitespaces)) {
            if parsed > declaredLength {
                declaredLength = parsed
            }
        }

        if declaredLength > 0 && declaredLength > Int64(maxResponseBodyBytes) {
            sizeExceeded = true
            self.error = NSError(
                domain: "RuntimeNetwork",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "HTTP response body size exceeds limit of \(maxResponseBodyBytes) bytes"]
            )
            lock.unlock()
            completionHandler(.cancel)
            return
        }

        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        defer { lock.unlock() }
        if sizeExceeded { return }

        let newTotal = receivedByteCount + data.count
        if newTotal > maxResponseBodyBytes {
            sizeExceeded = true
            self.error = NSError(
                domain: "RuntimeNetwork",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "HTTP response body size exceeds limit of \(maxResponseBodyBytes) bytes"]
            )
            dataTask.cancel()
            return
        }

        receivedByteCount = newTotal
        decoder.append(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        defer {
            lock.unlock()
            semaphore.signal()
        }

        if sizeExceeded {
            // Error was already recorded as size-exceeded error
        } else if let error = error {
            self.error = error
        } else {
            decoder.finish()
            self.responseBody = decoder.string
        }
    }

    private static func sameOrigin(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhsKey = runtimeOriginKey(lhs), let rhsKey = runtimeOriginKey(rhs) else { return false }
        return lhsKey == rhsKey
    }
}

private func runtimeHttpRequestBuilderBox(from raw: Int) -> RuntimeHttpRequestBuilderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHttpRequestBuilderBox.self)
}

private func runtimeHttpRequestBox(from raw: Int) -> RuntimeHttpRequestBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHttpRequestBox.self)
}

private func runtimeHttpBodyPublisherBox(from raw: Int) -> RuntimeHttpBodyPublisherBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHttpBodyPublisherBox.self)
}

private func runtimeHttpBodyHandlerBox(from raw: Int) -> RuntimeHttpBodyHandlerBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHttpBodyHandlerBox.self)
}

private func runtimeHttpResponseBox(from raw: Int) -> RuntimeHttpResponseBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHttpResponseBox.self)
}

private func runtimeHttpHeadersBox(from raw: Int) -> RuntimeHttpHeadersBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHttpHeadersBox.self)
}

private func networkString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let str = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return str
}

private func networkStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

private func runtimeHTTPClientBox(from raw: Int) -> RuntimeHTTPClientBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHTTPClientBox.self)
}

/// URI handles remain an internal Network handoff for HTTP request builders.
/// The public java.net.URI compiler/runtime surface is intentionally removed.
final class RuntimeNetworkURIBox {
    let components: URLComponents

    init(components: URLComponents) {
        self.components = components
    }
}

/// Build the URI handle consumed by the HTTP request builder's internal ABI.
/// This keeps Network tests independent from the removed `kk_uri_new` export.
func runtimeNetworkURI(from specRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let spec = networkString(from: specRaw, caller: #function)
    guard let components = URLComponents(string: spec) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "URISyntaxException: \(spec)")
        return 0
    }
    return registerRuntimeObject(RuntimeNetworkURIBox(components: components))
}

private func networkURL(from uriRaw: Int) -> URL? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: uriRaw),
          let uriBox = tryCast(ptr, to: RuntimeNetworkURIBox.self)
    else {
        return nil
    }
    return uriBox.components.url
}

private func networkHeaderPairs(from response: HTTPURLResponse?) -> [(String, [String])] {
    guard let response else { return [] }
    var pairs: [(String, [String])] = []
    for (rawKey, rawValue) in response.allHeaderFields {
        guard let key = rawKey as? String else { continue }
        if let values = rawValue as? [String] {
            pairs.append((key, values))
        } else {
            pairs.append((key, ["\(rawValue)"]))
        }
    }
    pairs.sort { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    return pairs
}

private func networkHeaderMapRaw(_ headers: [(String, [String])]) -> Int {
    let keys = headers.map { networkStringRaw($0.0) }
    let values = headers.map { header in
        registerRuntimeObject(RuntimeListBox(elements: header.1.map(networkStringRaw)))
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
}

private func networkHeaderFirstValue(_ headers: [(String, [String])], name: String) -> String? {
    headers.first(where: { $0.0.caseInsensitiveCompare(name) == .orderedSame })?.1.first
}

@_cdecl("kk_http_client_newHttpClient")
public func kk_http_client_newHttpClient() -> Int {
    registerRuntimeObject(RuntimeHTTPClientBox())
}

@_cdecl("kk_http_request_newBuilder")
public func kk_http_request_newBuilder() -> Int {
    registerRuntimeObject(RuntimeHttpRequestBuilderBox())
}

@_cdecl("kk_http_request_newBuilder_uri")
public func kk_http_request_newBuilder_uri(_ uriRaw: Int) -> Int {
    registerRuntimeObject(RuntimeHttpRequestBuilderBox(url: networkURL(from: uriRaw)))
}

@_cdecl("kk_http_request_builder_uri")
public func kk_http_request_builder_uri(_ builderRaw: Int, _ uriRaw: Int) -> Int {
    guard let builder = runtimeHttpRequestBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_request_builder_uri received invalid builder handle")
    }
    builder.url = networkURL(from: uriRaw)
    return builderRaw
}

@_cdecl("kk_http_request_builder_header")
public func kk_http_request_builder_header(_ builderRaw: Int, _ nameRaw: Int, _ valueRaw: Int) -> Int {
    guard let builder = runtimeHttpRequestBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_request_builder_header received invalid builder handle")
    }
    builder.headers.append((networkString(from: nameRaw, caller: #function), networkString(from: valueRaw, caller: #function)))
    return builderRaw
}

@_cdecl("kk_http_request_builder_GET")
public func kk_http_request_builder_GET(_ builderRaw: Int) -> Int {
    guard let builder = runtimeHttpRequestBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_request_builder_GET received invalid builder handle")
    }
    builder.method = "GET"
    builder.body = nil
    return builderRaw
}

@_cdecl("kk_http_request_builder_POST")
public func kk_http_request_builder_POST(_ builderRaw: Int, _ publisherRaw: Int) -> Int {
    guard let builder = runtimeHttpRequestBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_request_builder_POST received invalid builder handle")
    }
    guard let publisher = runtimeHttpBodyPublisherBox(from: publisherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_request_builder_POST received invalid body publisher handle")
    }
    builder.method = "POST"
    builder.body = publisher.data
    return builderRaw
}

@_cdecl("kk_http_request_builder_build")
public func kk_http_request_builder_build(_ builderRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let builder = runtimeHttpRequestBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_request_builder_build received invalid builder handle")
    }
    guard let url = builder.url else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "HTTP request URI is not set")
        return 0
    }
    return registerRuntimeObject(RuntimeHttpRequestBox(url: url, method: builder.method, headers: builder.headers, body: builder.body))
}

@_cdecl("kk_http_body_publishers_noBody")
public func kk_http_body_publishers_noBody(_ bodyPublishersRaw: Int) -> Int {
    _ = bodyPublishersRaw
    return registerRuntimeObject(RuntimeHttpBodyPublisherBox(data: nil))
}

@_cdecl("kk_http_body_publishers_ofString")
public func kk_http_body_publishers_ofString(_ bodyPublishersRaw: Int, _ bodyRaw: Int) -> Int {
    _ = bodyPublishersRaw
    let text = networkString(from: bodyRaw, caller: #function)
    return registerRuntimeObject(RuntimeHttpBodyPublisherBox(data: text.data(using: .utf8) ?? Data()))
}

@_cdecl("kk_http_body_handlers_ofString")
public func kk_http_body_handlers_ofString(_ bodyHandlersRaw: Int) -> Int {
    _ = bodyHandlersRaw
    return registerRuntimeObject(RuntimeHttpBodyHandlerBox(kind: "string"))
}

@_cdecl("kk_http_client_send")
public func kk_http_client_send(_ clientRaw: Int, _ requestRaw: Int, _ bodyHandlerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_send received invalid client handle")
    }
    guard let request = runtimeHttpRequestBox(from: requestRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_send received invalid request handle")
    }
    guard let bodyHandler = runtimeHttpBodyHandlerBox(from: bodyHandlerRaw), bodyHandler.kind == "string" else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_send received invalid body handler handle")
    }

    let config = client.snapshot()
    let readTimeout = config.readTimeoutMillis > 0 ? Double(config.readTimeoutMillis) / 1000 : Double.infinity

    var urlRequest = URLRequest(url: request.url)
    urlRequest.httpMethod = request.method
    urlRequest.httpBody = request.body
    urlRequest.timeoutInterval = readTimeout
    // Per-request headers win: a request that sets a header (e.g. Authorization)
    // suppresses the client-level default/bearer for that field rather than
    // appending to it, which would produce a malformed combined value.
    let requestHeaderNames = Set(request.headers.map { $0.0.lowercased() })
    for (name, value) in config.defaultHeaders where !requestHeaderNames.contains(name.lowercased()) {
        urlRequest.setValue(value, forHTTPHeaderField: name)
    }
    if let authHeader = config.authHeader, !requestHeaderNames.contains("authorization") {
        urlRequest.setValue(authHeader, forHTTPHeaderField: "Authorization")
    }
    for (name, value) in request.headers {
        urlRequest.addValue(value, forHTTPHeaderField: name)
    }

    // Create a fresh client-scoped session for this send instead of
    // URLSession.shared so mutable redirect policy, timeouts, and credential
    // storage cannot leak across clients or sends. Reusing sessions would need
    // invalidation whenever those settings change.
    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.httpShouldSetCookies = false
    sessionConfig.httpCookieStorage = nil
    sessionConfig.urlCredentialStorage = nil
    if config.connectTimeoutMillis > 0 {
        // URLSession has no TCP-connect-only timeout; map the Java-style
        // connect timeout to the closest available request-phase bound.
        sessionConfig.timeoutIntervalForRequest = Double(config.connectTimeoutMillis) / 1000
    }
    // Only cap total resource time when both timeouts are bounded; a value of 0
    // means "no limit", so summing would otherwise treat a disabled timeout as 0ms.
    if config.connectTimeoutMillis > 0, config.readTimeoutMillis > 0 {
        sessionConfig.timeoutIntervalForResource = Double(config.connectTimeoutMillis + config.readTimeoutMillis) / 1000
    }

    let delegate = RuntimeHTTPSessionDelegate(
        followRedirects: config.followRedirects,
        trustedRedirectOrigins: config.trustedRedirectOrigins,
        maxResponseBodyBytes: config.maxResponseBodyBytes
    )
    let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }

    let task = session.dataTask(with: urlRequest)
    task.resume()

    let (httpResponseOpt, body, responseErrorOpt) = delegate.waitForResult()

    if let responseError = responseErrorOpt {
        outThrown?.pointee = runtimeAllocateIOException(message: responseError.localizedDescription)
        return 0
    }

    guard let httpResponse = httpResponseOpt else {
        outThrown?.pointee = runtimeAllocateIOException(message: "Missing HTTP response")
        return 0
    }

    let responseBox = RuntimeHttpResponseBox(
        statusCode: httpResponse.statusCode,
        headers: networkHeaderPairs(from: httpResponse),
        body: body
    )
    return registerRuntimeObject(responseBox)
}

@_cdecl("kk_http_response_statusCode")
public func kk_http_response_statusCode(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_statusCode received invalid response handle")
    }
    return response.statusCode
}

@_cdecl("kk_http_response_body")
public func kk_http_response_body(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_body received invalid response handle")
    }
    return networkStringRaw(response.body)
}

@_cdecl("kk_http_response_headers")
public func kk_http_response_headers(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_headers received invalid response handle")
    }
    return registerRuntimeObject(RuntimeHttpHeadersBox(headers: response.headers))
}

@_cdecl("kk_http_headers_map")
public func kk_http_headers_map(_ headersRaw: Int) -> Int {
    guard let headers = runtimeHttpHeadersBox(from: headersRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_headers_map received invalid headers handle")
    }
    return networkHeaderMapRaw(headers.headers)
}

@_cdecl("kk_http_headers_firstValue")
public func kk_http_headers_firstValue(_ headersRaw: Int, _ nameRaw: Int) -> Int {
    guard let headers = runtimeHttpHeadersBox(from: headersRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_headers_firstValue received invalid headers handle")
    }
    let name = networkString(from: nameRaw, caller: #function)
    guard let value = networkHeaderFirstValue(headers.headers, name: name) else {
        return runtimeNullSentinelInt
    }
    return networkStringRaw(value)
}

@_cdecl("kk_http_client_setConnectTimeoutMillis")
public func kk_http_client_setConnectTimeoutMillis(_ clientRaw: Int, _ timeoutMillis: Int) -> Int {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_setConnectTimeoutMillis received invalid client handle")
    }
    client.setConnectTimeoutMillis(timeoutMillis)
    return 0
}

@_cdecl("kk_http_client_setReadTimeoutMillis")
public func kk_http_client_setReadTimeoutMillis(_ clientRaw: Int, _ timeoutMillis: Int) -> Int {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_setReadTimeoutMillis received invalid client handle")
    }
    client.setReadTimeoutMillis(timeoutMillis)
    return 0
}

@_cdecl("kk_http_client_setFollowRedirects")
public func kk_http_client_setFollowRedirects(_ clientRaw: Int, _ enabled: Int) -> Int {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_setFollowRedirects received invalid client handle")
    }
    client.setFollowRedirects(enabled != 0)
    return 0
}

@_cdecl("kk_http_client_setBearerToken")
public func kk_http_client_setBearerToken(_ clientRaw: Int, _ tokenRaw: Int) -> Int {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_setBearerToken received invalid client handle")
    }
    client.setBearerToken(networkString(from: tokenRaw, caller: #function))
    return 0
}

@_cdecl("kk_http_client_addTrustedRedirectOrigin")
public func kk_http_client_addTrustedRedirectOrigin(_ clientRaw: Int, _ originRaw: Int) -> Int {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_addTrustedRedirectOrigin received invalid client handle")
    }
    let spec = networkString(from: originRaw, caller: #function)
    if let key = runtimeOriginKey(URL(string: spec)) {
        client.addTrustedRedirectOrigin(key)
    }
    return 0
}

@_cdecl("kk_http_client_setMaxResponseBodyBytes")
public func kk_http_client_setMaxResponseBodyBytes(_ clientRaw: Int, _ limit: Int) -> Int {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_setMaxResponseBodyBytes received invalid client handle")
    }
    client.setMaxResponseBodyBytes(limit)
    return 0
}

@_cdecl("kk_http_response_url")
public func kk_http_response_url(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_url received invalid response handle")
    }
    return networkStringRaw(response.url)
}

@_cdecl("kk_http_response_errorMessage")
public func kk_http_response_errorMessage(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_errorMessage received invalid response handle")
    }
    guard let errorMessage = response.errorMessage else { return runtimeNullSentinelInt }
    return networkStringRaw(errorMessage)
}

@_cdecl("kk_http_response_timedOut")
public func kk_http_response_timedOut(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_timedOut received invalid response handle")
    }
    return response.timedOut ? 1 : 0
}

@_cdecl("kk_http_response_isSuccessful")
public func kk_http_response_isSuccessful(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_isSuccessful received invalid response handle")
    }
    return response.isSuccessful ? 1 : 0
}

@_cdecl("kk_http_response_header")
public func kk_http_response_header(_ responseRaw: Int, _ nameRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_header received invalid response handle")
    }
    let name = networkString(from: nameRaw, caller: #function)
    guard let value = networkHeaderFirstValue(response.headers, name: name) else {
        return runtimeNullSentinelInt
    }
    return networkStringRaw(value)
}
