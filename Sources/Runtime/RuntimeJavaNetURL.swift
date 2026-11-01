import Foundation
import RuntimeABI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Input stream boxes that carry a fully-typed Kotlin throwable for the next
/// `outThrown` report. `RuntimeSocketInputStreamBox` uses this to surface
/// `SocketTimeoutException`/`SocketException` rather than a plain IOException.
protocol RuntimeInputStreamThrowableCarrier {
    var pendingReadThrowable: Int { get }
}

// MARK: - URLConnection box

private final class RuntimeURLConnectionBox {
    let spec: String
    var method = "GET"
    var doOutput = false
    var bodyBuffer = Data()
    var connected = false
    var responseCode = -1
    var responseMessage: String?
    var headerFields: [(String, [String])] = []
    var bodyData = Data()
    var connectFailed: String?

    init(spec: String) {
        self.spec = spec
    }
}

private func javaNetURLConnection(_ raw: Int) -> RuntimeURLConnectionBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeURLConnectionBox.self)
}

private func javaNetURLString(_ raw: Int) -> String? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let surrogate = extractString(from: ptr)
    else { return nil }
    return KotlinStringSurrogateEncoding.unicodeString(surrogate)
}

private func javaNetFilePath(from spec: String) -> String? {
    guard spec.lowercased().hasPrefix("file:") else { return nil }
    var rest = String(spec.dropFirst(5))
    if rest.hasPrefix("//") {
        rest = String(rest.dropFirst(2))
        if let slash = rest.firstIndex(of: "/") {
            rest = String(rest[slash...])
        } else {
            rest = ""
        }
    }
    let fragmentSplit = rest.split(separator: "#", maxSplits: 1)
    rest = String(fragmentSplit.first ?? "")
    let querySplit = rest.split(separator: "?", maxSplits: 1)
    rest = String(querySplit.first ?? "")
    return rest.removingPercentEncoding ?? rest
}

private func javaNetPerformConnect(
    _ box: RuntimeURLConnectionBox,
    serializedHeaders: String,
    connectTimeoutMs: Int,
    readTimeoutMs: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Bool {
    outThrown?.pointee = 0
    let spec = box.spec
    let timeout = max(connectTimeoutMs, readTimeoutMs)
    let timeoutSeconds = timeout > 0 ? TimeInterval(timeout) / 1000.0 : 60.0

    if let path = javaNetFilePath(from: spec) {
        guard FileManager.default.fileExists(atPath: path) else {
            outThrown?.pointee = runtimeAllocateIOException(message: "\(path) (No such file or directory)")
            return false
        }
        do {
            box.bodyData = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            outThrown?.pointee = runtimeAllocateIOException(message: error.localizedDescription)
            return false
        }
        box.responseCode = -1
        box.responseMessage = nil
        var headers: [(String, [String])] = []
        headers.append(("content-length", ["\(box.bodyData.count)"]))
        box.headerFields = headers
        box.connected = true
        return true
    }

    guard let url = Foundation.URL(string: spec) else {
        outThrown?.pointee = runtimeAllocateJavaNetExceptionShared(
            "java.net.MalformedURLException", "MalformedURLException", ["java.io.IOException"], spec)
        return false
    }

    var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
    request.httpMethod = box.method
    if !serializedHeaders.isEmpty {
        for pair in serializedHeaders.components(separatedBy: "\u{2}") {
            guard let sep = pair.firstIndex(of: "\u{1}") else { continue }
            let name = String(pair[pair.startIndex ..< sep])
            let value = String(pair[pair.index(after: sep)...])
            request.setValue(value, forHTTPHeaderField: name)
        }
    }
    if box.doOutput && !box.bodyBuffer.isEmpty {
        request.httpBody = box.bodyBuffer
    }

    let semaphore = DispatchSemaphore(value: 0)
    final class ResultBox: @unchecked Sendable { var data = Data(); var response: HTTPURLResponse?; var error: Error? }
    let resultBox = ResultBox()
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let data { resultBox.data = data }
        resultBox.response = response as? HTTPURLResponse
        resultBox.error = error
        semaphore.signal()
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + timeoutSeconds + 5)

    if let error = resultBox.error {
        let nsError = error as NSError
        if nsError.code == NSURLErrorTimedOut {
            outThrown?.pointee = runtimeAllocateJavaNetExceptionShared(
            "java.net.SocketTimeoutException", "SocketTimeoutException",
            ["java.io.InterruptedIOException", "java.io.IOException"], "connect timed out")
        } else if nsError.code == NSURLErrorCannotFindHost || nsError.code == NSURLErrorDNSLookupFailed {
            outThrown?.pointee = runtimeAllocateJavaNetExceptionShared(
            "java.net.UnknownHostException", "UnknownHostException",
            ["java.io.IOException"], url.host ?? spec)
        } else {
            outThrown?.pointee = runtimeAllocateJavaNetExceptionShared(
            "java.net.SocketException", "SocketException",
            ["java.io.IOException"], error.localizedDescription)
        }
        return false
    }
    guard let httpResponse = resultBox.response else {
        outThrown?.pointee = runtimeAllocateIOException(message: "No HTTP response")
        return false
    }
    box.responseCode = httpResponse.statusCode
    box.responseMessage = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
    var headers: [(String, [String])] = []
    for (key, value) in httpResponse.allHeaderFields {
        guard let name = key as? String else { continue }
        if let values = value as? [String] {
            headers.append((name, values))
        } else {
            headers.append((name, ["\(value)"]))
        }
    }
    headers.sort { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    box.headerFields = headers
    box.bodyData = resultBox.data
    box.connected = true
    return true
}

@_cdecl("__kk_net_url_open_stream")
public func __kk_net_url_open_stream(_ specRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let spec = javaNetURLString(specRaw) ?? ""
    let box = RuntimeURLConnectionBox(spec: spec)
    guard javaNetPerformConnect(box, serializedHeaders: "", connectTimeoutMs: 0, readTimeoutMs: 0, outThrown: outThrown) else {
        return 0
    }
    return runtimeRegisterIoStream(
        RuntimeInputStreamBox(data: box.bodyData),
        fqName: "java.io.InputStream", input: true
    )
}

@_cdecl("__kk_net_url_connection_new")
public func __kk_net_url_connection_new(_ specRaw: Int) -> Int {
    let spec = javaNetURLString(specRaw) ?? ""
    return registerRuntimeObject(RuntimeURLConnectionBox(spec: spec))
}

@_cdecl("__kk_net_url_connection_set_method")
public func __kk_net_url_connection_set_method(_ boxRaw: Int, _ methodRaw: Int) {
    guard let box = javaNetURLConnection(boxRaw) else { return }
    box.method = javaNetURLString(methodRaw) ?? "GET"
}

@_cdecl("__kk_net_url_connection_set_do_output")
public func __kk_net_url_connection_set_do_output(_ boxRaw: Int, _ value: Int) {
    javaNetURLConnection(boxRaw)?.doOutput = value != 0
}

@_cdecl("__kk_net_url_connection_connect")
public func __kk_net_url_connection_connect(
    _ boxRaw: Int, _ headersRaw: Int, _ connectTimeoutMs: Int, _ readTimeoutMs: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) {
    guard let box = javaNetURLConnection(boxRaw) else { return }
    _ = javaNetPerformConnect(
        box,
        serializedHeaders: javaNetURLString(headersRaw) ?? "",
        connectTimeoutMs: connectTimeoutMs,
        readTimeoutMs: readTimeoutMs,
        outThrown: outThrown
    )
}

@_cdecl("__kk_net_url_connection_input_stream")
public func __kk_net_url_connection_input_stream(_ boxRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let box = javaNetURLConnection(boxRaw), box.connected else {
        outThrown?.pointee = runtimeAllocateIOException(message: "not connected")
        return 0
    }
    return runtimeRegisterIoStream(
        RuntimeInputStreamBox(data: box.bodyData),
        fqName: "java.io.InputStream", input: true
    )
}

private final class RuntimeURLConnectionBodySink: RuntimeOutputStreamSink {
    let box: RuntimeURLConnectionBox

    init(box: RuntimeURLConnectionBox) {
        self.box = box
    }

    func write(_ data: Data) throws {
        box.bodyBuffer.append(data)
    }

    func flush() throws {}
    func close() {}
}

@_cdecl("__kk_net_url_connection_output_stream")
public func __kk_net_url_connection_output_stream(_ boxRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let box = javaNetURLConnection(boxRaw) else {
        outThrown?.pointee = runtimeAllocateIOException(message: "invalid connection")
        return 0
    }
    return runtimeRegisterIoStream(
        RuntimeOutputStreamBox(sink: RuntimeURLConnectionBodySink(box: box)),
        fqName: "java.io.OutputStream", input: false
    )
}

@_cdecl("__kk_net_url_connection_body_text")
public func __kk_net_url_connection_body_text(_ boxRaw: Int) -> Int {
    guard let box = javaNetURLConnection(boxRaw) else { return runtimeNullSentinelInt }
    return runtimeMakeUTF8StringRaw(String(decoding: box.bodyData, as: UTF8.self))
}

@_cdecl("__kk_net_url_connection_header")
public func __kk_net_url_connection_header(_ boxRaw: Int, _ nameRaw: Int) -> Int {
    guard let box = javaNetURLConnection(boxRaw) else { return runtimeNullSentinelInt }
    let name = (javaNetURLString(nameRaw) ?? "").lowercased()
    guard let value = box.headerFields.first(where: { $0.0.lowercased() == name })?.1.first else {
        return runtimeNullSentinelInt
    }
    return runtimeMakeUTF8StringRaw(value)
}

@_cdecl("__kk_net_url_connection_header_long")
public func __kk_net_url_connection_header_long(_ boxRaw: Int, _ nameRaw: Int) -> Int {
    guard let box = javaNetURLConnection(boxRaw) else { return 0 }
    let name = (javaNetURLString(nameRaw) ?? "").lowercased()
    guard let value = box.headerFields.first(where: { $0.0.lowercased() == name })?.1.first,
          let parsed = Int(value.trimmingCharacters(in: .whitespaces))
    else { return 0 }
    return parsed
}

@_cdecl("__kk_net_url_connection_header_at")
public func __kk_net_url_connection_header_at(_ boxRaw: Int, _ index: Int) -> Int {
    guard let box = javaNetURLConnection(boxRaw), index >= 0, index < box.headerFields.count,
          let value = box.headerFields[index].1.first
    else { return runtimeNullSentinelInt }
    return runtimeMakeUTF8StringRaw(value)
}

@_cdecl("__kk_net_url_connection_header_key_at")
public func __kk_net_url_connection_header_key_at(_ boxRaw: Int, _ index: Int) -> Int {
    guard let box = javaNetURLConnection(boxRaw), index >= 0, index < box.headerFields.count else {
        return runtimeNullSentinelInt
    }
    return runtimeMakeUTF8StringRaw(box.headerFields[index].0)
}

@_cdecl("__kk_net_url_connection_headers_map")
public func __kk_net_url_connection_headers_map(_ boxRaw: Int) -> Int {
    guard let box = javaNetURLConnection(boxRaw) else { return runtimeMakeUTF8StringRaw("") }
    let serialized = box.headerFields.map { name, values in
        values.map { "\(name)\u{1}\($0)" }.joined(separator: "\u{2}")
    }.joined(separator: "\u{2}")
    return runtimeMakeUTF8StringRaw(serialized)
}

@_cdecl("__kk_net_url_connection_response_code")
public func __kk_net_url_connection_response_code(_ boxRaw: Int) -> Int {
    javaNetURLConnection(boxRaw)?.responseCode ?? -1
}

@_cdecl("__kk_net_url_connection_response_message")
public func __kk_net_url_connection_response_message(_ boxRaw: Int) -> Int {
    guard let message = javaNetURLConnection(boxRaw)?.responseMessage else { return runtimeNullSentinelInt }
    return runtimeMakeUTF8StringRaw(message)
}

@_cdecl("__kk_net_url_connection_disconnect")
public func __kk_net_url_connection_disconnect(_ boxRaw: Int) {
    javaNetURLConnection(boxRaw)?.connected = false
}

// MARK: - AWT: headless detection and pointer location

private func runtimeIsHeadless() -> Bool {
    if let env = ProcessInfo.processInfo.environment["KSWIFTK_HEADLESS"] {
        return env == "1" || env.lowercased() == "true"
    }
    #if canImport(CoreGraphics)
    return CGMainDisplayID() == 0
    #else
    return true
    #endif
}

@_cdecl("__kk_awt_is_headless")
public func __kk_awt_is_headless() -> Int {
    runtimeIsHeadless() ? 1 : 0
}

@_cdecl("__kk_awt_pointer_location")
public func __kk_awt_pointer_location(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if runtimeIsHeadless() {
        outThrown?.pointee = runtimeAllocateJavaNetExceptionShared(
            "java.awt.HeadlessException", "HeadlessException",
            ["java.lang.UnsupportedOperationException", "kotlin.UnsupportedOperationException",
             "kotlin.RuntimeException"], nil)
        return 0
    }
    #if canImport(CoreGraphics)
    let point = CGEvent(source: nil)?.location ?? .zero
    let x = UInt64(UInt32(truncatingIfNeeded: Int64(bitPattern: UInt64(Int(point.x)))))
    let y = UInt64(UInt32(truncatingIfNeeded: Int64(bitPattern: UInt64(Int(point.y)))))
    return Int(x << 32 | y)
    #else
    return 0
    #endif
}
