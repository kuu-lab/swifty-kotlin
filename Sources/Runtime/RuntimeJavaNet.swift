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

// MARK: - Throwable boxes for java.net / java.awt exceptions

private final class RuntimeJavaNetExceptionBox: RuntimeThrowableBox {
    private let fqName: String
    private let simpleName: String
    private let extraParents: [String]

    init(fqName: String, simpleName: String, extraParents: [String], message: String?, messageRaw: Int = 0) {
        self.fqName = fqName
        self.simpleName = simpleName
        self.extraParents = extraParents
        super.init(message: message, messageRaw: messageRaw)
    }

    override var exceptionFQName: String { fqName }

    override var exceptionHierarchyFQNames: [String] {
        [fqName, simpleName] + extraParents + ["kotlin.Exception", "kotlin.Throwable"]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage(simpleName, message)
    }
}

func runtimeAllocateJavaNetExceptionShared(
    _ fqName: String, _ simpleName: String, _ parents: [String], _ message: String?
) -> Int {
    registerRuntimeObject(RuntimeJavaNetExceptionBox(
        fqName: fqName, simpleName: simpleName, extraParents: parents, message: message
    ))
}

private func runtimeAllocateSocketException(_ message: String) -> Int {
    runtimeAllocateJavaNetExceptionShared(
        "java.net.SocketException", "SocketException",
        ["java.io.IOException"], message)
}

private func runtimeAllocateConnectException(_ message: String) -> Int {
    runtimeAllocateJavaNetExceptionShared(
        "java.net.ConnectException", "ConnectException",
        ["java.net.SocketException", "java.io.IOException"], message)
}

private func runtimeAllocateBindException(_ message: String) -> Int {
    runtimeAllocateJavaNetExceptionShared(
        "java.net.BindException", "BindException",
        ["java.net.SocketException", "java.io.IOException"], message)
}

private func runtimeAllocateUnknownHostException(_ host: String) -> Int {
    runtimeAllocateJavaNetExceptionShared(
        "java.net.UnknownHostException", "UnknownHostException",
        ["java.io.IOException"], host)
}

private func runtimeAllocateSocketTimeoutException(_ message: String) -> Int {
    runtimeAllocateJavaNetExceptionShared(
        "java.net.SocketTimeoutException", "SocketTimeoutException",
        ["java.io.InterruptedIOException", "java.io.IOException"], message)
}

private func runtimeAllocateNoRouteToHostException(_ message: String) -> Int {
    runtimeAllocateJavaNetExceptionShared(
        "java.net.NoRouteToHostException", "NoRouteToHostException",
        ["java.net.SocketException", "java.io.IOException"], message)
}

private func runtimeAllocateHeadlessException() -> Int {
    runtimeAllocateJavaNetExceptionShared(
        "java.awt.HeadlessException", "HeadlessException",
        ["java.lang.UnsupportedOperationException", "kotlin.UnsupportedOperationException",
         "kotlin.RuntimeException"], nil)
}

private func javaNetString(_ raw: Int) -> String? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let surrogate = extractString(from: ptr)
    else { return nil }
    return KotlinStringSurrogateEncoding.unicodeString(surrogate)
}

private func javaNetErrorMessage(_ code: Int32) -> String {
    String(cString: strerror(code))
}

/// Formats a numeric host the way the JDK `InetAddress.getHostAddress` does:
/// IPv6 is uncompressed eight-group lowercase hex without leading zeros, and
/// IPv4-mapped `::ffff:a.b.c.d` collapses to the IPv4 form (the JDK models it
/// as an `Inet4Address`). A `%zone` scope suffix is preserved.
private func javaNetNumericHost(_ text: String) -> String {
    guard text.contains(":") else { return text }
    var scope = ""
    var numeric = text
    if let percent = text.firstIndex(of: "%") {
        scope = String(text[percent...])
        numeric = String(text[..<percent])
    }
    var bytes = in6_addr()
    guard inet_pton(AF_INET6, numeric, &bytes) == 1 else { return text }
    let raw = withUnsafeBytes(of: &bytes) { [UInt8]($0) }
    let mapped = raw[0 ..< 10].allSatisfy { $0 == 0 } && raw[10] == 0xff && raw[11] == 0xff
    if mapped {
        return "\(raw[12]).\(raw[13]).\(raw[14]).\(raw[15])"
    }
    let groups = stride(from: 0, to: 16, by: 2).map {
        String((Int(raw[$0]) << 8) | Int(raw[$0 + 1]), radix: 16)
    }
    return groups.joined(separator: ":") + scope
}

// MARK: - DNS / InetAddress

private func javaNetResolveAll(_ host: String) -> [String] {
    var hints = addrinfo()
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &result) == 0, let list = result else {
        return []
    }
    defer { freeaddrinfo(list) }
    var addresses: [String] = []
    var seen = Set<String>()
    var current = list
    while true {
        let info = current.pointee
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(info.ai_addr, info.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
            let text = javaNetNumericHost(String(cString: buffer))
            if !seen.contains(text) {
                seen.insert(text)
                addresses.append(text)
            }
        }
        guard let next = info.ai_next else { break }
        current = next
    }
    return addresses
}

@_cdecl("__kk_net_resolve")
public func __kk_net_resolve(_ hostRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let host = javaNetString(hostRaw) ?? ""
    let addresses = javaNetResolveAll(host)
    if addresses.isEmpty {
        outThrown?.pointee = runtimeAllocateUnknownHostException(host)
        return 0
    }
    return runtimeMakeUTF8StringRaw(addresses.joined(separator: " "))
}

@_cdecl("__kk_net_reverse_lookup")
public func __kk_net_reverse_lookup(_ addressRaw: Int) -> Int {
    let address = javaNetString(addressRaw) ?? ""
    var storage = sockaddr_storage()
    var length: socklen_t = 0
    if address.contains(":") {
        var sa = sockaddr_in6()
        if inet_pton(AF_INET6, address, &sa.sin6_addr) == 1 {
            sa.sin6_family = sa_family_t(AF_INET6)
            sa.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            length = socklen_t(MemoryLayout<sockaddr_in6>.size)
            memcpy(&storage, &sa, Int(length))
        }
    } else {
        var sa = sockaddr_in()
        if inet_pton(AF_INET, address, &sa.sin_addr) == 1 {
            sa.sin_family = sa_family_t(AF_INET)
            #if canImport(Darwin)
            sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            #endif
            length = socklen_t(MemoryLayout<sockaddr_in>.size)
            memcpy(&storage, &sa, Int(length))
        }
    }
    guard length > 0 else { return runtimeMakeUTF8StringRaw("") }
    var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    let ok = withUnsafePointer(to: &storage) { ptr -> Int32 in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            getnameinfo(sa, length, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NAMEREQD)
        }
    }
    guard ok == 0 else { return runtimeMakeUTF8StringRaw("") }
    return runtimeMakeUTF8StringRaw(String(cString: hostBuffer))
}

@_cdecl("__kk_net_local_host_name")
public func __kk_net_local_host_name() -> Int {
    var name = [CChar](repeating: 0, count: 256)
    if gethostname(&name, name.count) == 0 {
        return runtimeMakeUTF8StringRaw(String(cString: name))
    }
    return runtimeMakeUTF8StringRaw("localhost")
}

// MARK: - Socket box

private enum JavaNetSocketOption {
    static let soTimeout = 0
    static let soReuseAddr = 1
    static let soKeepAlive = 2
    static let tcpNoDelay = 3
    static let soSndBuf = 4
    static let soRcvBuf = 5
}

final class RuntimeJavaNetSocketBox {
    var fd: Int32 = -1
    var connected = false
    var bound = false
    var closed = false
    var inputShutdown = false
    var outputShutdown = false
    var soTimeoutMillis = 0
    var remoteAddress: String?
    var remotePort = -1
    var localAddress: String?
    var localPort = -1

    var alive: Bool { fd >= 0 && !closed }

    func ensureSocket(family: Int32) -> Bool {
        if fd >= 0 { return true }
        let created = socket(family, SOCK_STREAM, 0)
        guard created >= 0 else { return false }
        fd = created
        #if canImport(Darwin)
        var noPipe: Int32 = 1
        _ = setsockopt(created, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout<Int32>.size))
        #endif
        return true
    }

    func refreshLocalPeer() {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var servBuffer = [CChar](repeating: 0, count: Int(NI_MAXSERV))
        if withUnsafeMutablePointer(to: &storage, { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }) == 0 {
            if withUnsafePointer(to: &storage, { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getnameinfo($0, length, &buffer, socklen_t(buffer.count), &servBuffer, socklen_t(servBuffer.count), NI_NUMERICHOST | NI_NUMERICSERV)
                }
            }) == 0 {
                localAddress = javaNetNumericHost(String(cString: buffer))
                localPort = Int(String(cString: servBuffer)) ?? -1
            }
        }
    }
}

private func javaNetSocket(_ raw: Int) -> RuntimeJavaNetSocketBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJavaNetSocketBox.self)
}

/// An input stream reading from a socket. Honors SO_RCVTIMEO (`setSoTimeout`):
/// a timed-out `recv` reports a pending `SocketTimeoutException` rather than
/// a plain `IOException`, matching `SocketInputStream` on the JVM.
private final class RuntimeSocketInputStreamBox: RuntimeInputStreamBox, RuntimeInputStreamThrowableCarrier, RuntimeChunkedInputStream {
    private let socket: RuntimeJavaNetSocketBox
    private var streamClosed = false
    private var throwable = 0

    init(socket: RuntimeJavaNetSocketBox) {
        self.socket = socket
        super.init(data: Data())
    }

    var pendingReadThrowable: Int {
        let value = throwable
        throwable = 0
        return value
    }

    override func readByte() -> Int {
        guard !streamClosed, socket.alive else { return -1 }
        var byte: UInt8 = 0
        while true {
            let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
            let count = recv(socket.fd, &byte, 1, 0)
            let readErrno = errno
            if gcBlocking { runtimeGCSafepoints.endBlocking() }
            if count == 1 { return Int(byte) }
            if count == 0 {
                socket.inputShutdown = true
                return -1
            }
            if readErrno == EINTR { continue }
            if readErrno == EAGAIN || readErrno == EWOULDBLOCK {
                throwable = runtimeAllocateSocketTimeoutException("Read timed out")
            } else if readErrno == ECONNRESET {
                throwable = runtimeAllocateSocketException("Connection reset")
            } else {
                throwable = runtimeAllocateSocketException(javaNetErrorMessage(readErrno))
            }
            return -1
        }
    }

    override func available() -> Int {
        // FIONREAD is not exposed to Swift on Darwin; report unknown.
        return 0
    }

    override func skip(_ count: Int) -> Int {
        var skipped = 0
        var scratch: UInt8 = 0
        while skipped < count {
            let got = recv(socket.fd, &scratch, 1, 0)
            if got <= 0 { break }
            skipped += 1
        }
        return skipped
    }

    /// One `recv` per call: a blocking stream must not loop for more data
    /// after the first successful read — JVM `read(byte[])` returns whatever a
    /// single read yields (at least one byte, or throws at timeout/EOF).
    func readChunk(_ maxCount: Int) -> [Int] {
        guard !streamClosed, socket.alive, maxCount > 0 else { return [] }
        var chunk = [UInt8](repeating: 0, count: maxCount)
        while true {
            let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
            let n = recv(socket.fd, &chunk, chunk.count, 0)
            let readErrno = errno
            if gcBlocking { runtimeGCSafepoints.endBlocking() }
            if n > 0 {
                return (0 ..< n).map { Int(Int8(bitPattern: chunk[$0])) }
            }
            if n == 0 {
                socket.inputShutdown = true
                return []
            }
            if readErrno == EINTR { continue }
            if readErrno == EAGAIN || readErrno == EWOULDBLOCK {
                throwable = runtimeAllocateSocketTimeoutException("Read timed out")
            } else if readErrno == ECONNRESET {
                throwable = runtimeAllocateSocketException("Connection reset")
            } else {
                throwable = runtimeAllocateSocketException(javaNetErrorMessage(readErrno))
            }
            return []
        }
    }

    override func readAllBytes() -> [Int] {
        var bytes: [Int] = []
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = recv(socket.fd, &chunk, chunk.count, 0)
            if n <= 0 {
                if n < 0 && errno == EINTR { continue }
                if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    throwable = runtimeAllocateSocketTimeoutException("Read timed out")
                }
                return bytes
            }
            for i in 0 ..< n { bytes.append(Int(Int8(bitPattern: chunk[i]))) }
        }
    }

    override func close() {
        if streamClosed { return }
        streamClosed = true
        if socket.alive && !socket.inputShutdown {
            shutdown(socket.fd, SHUT_RD)
            socket.inputShutdown = true
        }
    }
}

private final class RuntimeSocketOutputSink: RuntimeOutputStreamSink {
    private let socket: RuntimeJavaNetSocketBox
    private var streamClosed = false

    init(socket: RuntimeJavaNetSocketBox) {
        self.socket = socket
    }

    func write(_ data: Data) throws {
        guard !streamClosed, socket.alive else {
            throw RuntimeKotlinThrownError(thrownRaw: runtimeAllocateSocketException("Socket is closed"))
        }
        try data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < data.count {
                #if canImport(Darwin)
                let n = send(socket.fd, buffer.baseAddress!.advanced(by: sent), data.count - sent, 0)
                #else
                let n = send(socket.fd, buffer.baseAddress!.advanced(by: sent), data.count - sent, MSG_NOSIGNAL)
                #endif
                if n > 0 {
                    sent += n
                    continue
                }
                let writeErrno = errno
                if writeErrno == EINTR { continue }
                let thrown: Int
                if writeErrno == EPIPE {
                    thrown = runtimeAllocateSocketException("Broken pipe")
                } else if writeErrno == ECONNRESET {
                    thrown = runtimeAllocateSocketException("Connection reset")
                } else {
                    thrown = runtimeAllocateSocketException(javaNetErrorMessage(writeErrno))
                }
                throw RuntimeKotlinThrownError(thrownRaw: thrown)
            }
        }
    }

    func flush() throws {}

    func close() {
        if streamClosed { return }
        streamClosed = true
        if socket.alive && !socket.outputShutdown {
            shutdown(socket.fd, SHUT_WR)
            socket.outputShutdown = true
        }
    }
}

private func javaNetResolveSockaddr(_ host: String, port: Int) -> [(addr: sockaddr_storage, len: socklen_t)] {
    var hints = addrinfo()
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    hints.ai_flags = AI_NUMERICHOST
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, "\(port)", &hints, &result) == 0, let list = result else {
        return []
    }
    defer { freeaddrinfo(list) }
    var addrs: [(sockaddr_storage, socklen_t)] = []
    var current = list
    while true {
        var storage = sockaddr_storage()
        memcpy(&storage, current.pointee.ai_addr, Int(current.pointee.ai_addrlen))
        addrs.append((storage, current.pointee.ai_addrlen))
        guard let next = current.pointee.ai_next else { break }
        current = next
    }
    return addrs
}

@_cdecl("__kk_net_socket_create")
public func __kk_net_socket_create() -> Int {
    registerRuntimeObject(RuntimeJavaNetSocketBox())
}

@_cdecl("__kk_net_socket_connect")
public func __kk_net_socket_connect(
    _ boxRaw: Int, _ hostRaw: Int, _ port: Int, _ timeoutMillis: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) {
    outThrown?.pointee = 0
    guard let box = javaNetSocket(boxRaw) else { return }
    if box.closed {
        outThrown?.pointee = runtimeAllocateSocketException("Socket is closed")
        return
    }
    if box.connected {
        outThrown?.pointee = runtimeAllocateSocketException("already connected")
        return
    }
    let host = javaNetString(hostRaw) ?? ""
    let targets = javaNetResolveSockaddr(host, port: port)
    if targets.isEmpty {
        outThrown?.pointee = runtimeAllocateUnknownHostException(host)
        return
    }

    var lastError: Int32 = 0
    for (storage, length) in targets {
        var local = storage
        let family = Int32(local.ss_family)
        guard box.ensureSocket(family: family) else {
            outThrown?.pointee = runtimeAllocateSocketException(javaNetErrorMessage(errno))
            return
        }

        if timeoutMillis > 0 {
            let flags = fcntl(box.fd, F_GETFL, 0)
            _ = fcntl(box.fd, F_SETFL, flags | O_NONBLOCK)
            let result = withUnsafePointer(to: &local) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(box.fd, $0, length)
                }
            }
            if result != 0 && errno != EINPROGRESS {
                lastError = errno
                _ = fcntl(box.fd, F_SETFL, flags)
                continue
            }
            if result != 0 {
                var pollFd = pollfd(fd: box.fd, events: Int16(POLLOUT), revents: 0)
                let ready = poll(&pollFd, 1, Int32(timeoutMillis))
                _ = fcntl(box.fd, F_SETFL, flags)
                if ready <= 0 {
                    outThrown?.pointee = runtimeAllocateConnectException("connect timed out")
                    return
                }
                var soError: Int32 = 0
                var optLen = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(box.fd, SOL_SOCKET, SO_ERROR, &soError, &optLen)
                if soError != 0 {
                    lastError = soError
                    continue
                }
            }
        } else {
            let result = withUnsafePointer(to: &local) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(box.fd, $0, length)
                }
            }
            if result != 0 {
                lastError = errno
                continue
            }
        }

        box.connected = true
        box.bound = true
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var servBuffer = [CChar](repeating: 0, count: Int(NI_MAXSERV))
        _ = withUnsafePointer(to: &local) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, length, &hostBuffer, socklen_t(hostBuffer.count), &servBuffer, socklen_t(servBuffer.count), NI_NUMERICHOST | NI_NUMERICSERV)
            }
        }
        box.remoteAddress = javaNetNumericHost(String(cString: hostBuffer))
        box.remotePort = Int(String(cString: servBuffer)) ?? port
        box.refreshLocalPeer()
        return
    }

    switch lastError {
    case ECONNREFUSED:
        outThrown?.pointee = runtimeAllocateConnectException("Connection refused")
    case EHOSTUNREACH, ENETUNREACH:
        outThrown?.pointee = runtimeAllocateNoRouteToHostException(javaNetErrorMessage(lastError))
    case ETIMEDOUT:
        outThrown?.pointee = runtimeAllocateConnectException("connect timed out")
    default:
        outThrown?.pointee = runtimeAllocateSocketException(javaNetErrorMessage(lastError))
    }
}

@_cdecl("__kk_net_socket_bind")
public func __kk_net_socket_bind(
    _ boxRaw: Int, _ hostRaw: Int, _ port: Int, _ outThrown: UnsafeMutablePointer<Int>?
) {
    outThrown?.pointee = 0
    guard let box = javaNetSocket(boxRaw) else { return }
    let host = javaNetString(hostRaw) ?? "0.0.0.0"
    let targets = javaNetResolveSockaddr(host, port: port)
    guard let first = targets.first else {
        outThrown?.pointee = runtimeAllocateBindException("Can't assign requested address")
        return
    }
    var storage = first.addr
    guard box.ensureSocket(family: Int32(storage.ss_family)) else {
        outThrown?.pointee = runtimeAllocateSocketException(javaNetErrorMessage(errno))
        return
    }
    let result = withUnsafePointer(to: &storage) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(box.fd, $0, first.len)
        }
    }
    if result != 0 {
        let bindErrno = errno
        if bindErrno == EADDRINUSE {
            outThrown?.pointee = runtimeAllocateBindException("Address already in use")
        } else {
            outThrown?.pointee = runtimeAllocateBindException(javaNetErrorMessage(bindErrno))
        }
        return
    }
    box.bound = true
    box.refreshLocalPeer()
}

@_cdecl("__kk_net_socket_input_stream")
public func __kk_net_socket_input_stream(_ boxRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let box = javaNetSocket(boxRaw), box.connected, !box.closed else {
        outThrown?.pointee = runtimeAllocateSocketException("Socket is not connected")
        return 0
    }
    return runtimeRegisterIoStream(
        RuntimeSocketInputStreamBox(socket: box),
        fqName: "java.io.InputStream", input: true
    )
}

@_cdecl("__kk_net_socket_output_stream")
public func __kk_net_socket_output_stream(_ boxRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let box = javaNetSocket(boxRaw), box.connected, !box.closed else {
        outThrown?.pointee = runtimeAllocateSocketException("Socket is not connected")
        return 0
    }
    return runtimeRegisterIoStream(
        RuntimeOutputStreamBox(sink: RuntimeSocketOutputSink(socket: box)),
        fqName: "java.io.OutputStream", input: false
    )
}

@_cdecl("__kk_net_socket_close")
public func __kk_net_socket_close(_ boxRaw: Int) {
    guard let box = javaNetSocket(boxRaw), box.fd >= 0, !box.closed else { return }
    box.closed = true
    close(box.fd)
    box.fd = -1
}

@_cdecl("__kk_net_socket_is_closed")
public func __kk_net_socket_is_closed(_ boxRaw: Int) -> Int {
    (javaNetSocket(boxRaw)?.closed ?? true) ? 1 : 0
}

@_cdecl("__kk_net_socket_is_connected")
public func __kk_net_socket_is_connected(_ boxRaw: Int) -> Int {
    (javaNetSocket(boxRaw)?.connected ?? false) ? 1 : 0
}

@_cdecl("__kk_net_socket_is_bound")
public func __kk_net_socket_is_bound(_ boxRaw: Int) -> Int {
    (javaNetSocket(boxRaw)?.bound ?? false) ? 1 : 0
}

@_cdecl("__kk_net_socket_remote_address")
public func __kk_net_socket_remote_address(_ boxRaw: Int) -> Int {
    guard let address = javaNetSocket(boxRaw)?.remoteAddress else { return runtimeNullSentinelInt }
    return runtimeMakeUTF8StringRaw(address)
}

@_cdecl("__kk_net_socket_remote_port")
public func __kk_net_socket_remote_port(_ boxRaw: Int) -> Int {
    javaNetSocket(boxRaw)?.remotePort ?? -1
}

@_cdecl("__kk_net_socket_local_address")
public func __kk_net_socket_local_address(_ boxRaw: Int) -> Int {
    guard let address = javaNetSocket(boxRaw)?.localAddress else { return runtimeNullSentinelInt }
    return runtimeMakeUTF8StringRaw(address)
}

@_cdecl("__kk_net_socket_local_port")
public func __kk_net_socket_local_port(_ boxRaw: Int) -> Int {
    javaNetSocket(boxRaw)?.localPort ?? -1
}

@_cdecl("__kk_net_socket_get_option")
public func __kk_net_socket_get_option(_ boxRaw: Int, _ option: Int) -> Int {
    guard let box = javaNetSocket(boxRaw), box.fd >= 0 else { return 0 }
    switch option {
    case JavaNetSocketOption.soTimeout:
        var tv = timeval()
        var len = socklen_t(MemoryLayout<timeval>.size)
        if getsockopt(box.fd, SOL_SOCKET, SO_RCVTIMEO, &tv, &len) == 0 {
            return Int(tv.tv_sec) * 1000 + Int(tv.tv_usec) / 1000
        }
        return box.soTimeoutMillis
    case JavaNetSocketOption.soReuseAddr:
        var value: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        _ = getsockopt(box.fd, SOL_SOCKET, SO_REUSEADDR, &value, &len)
        return Int(value)
    case JavaNetSocketOption.soKeepAlive:
        var value: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        _ = getsockopt(box.fd, SOL_SOCKET, SO_KEEPALIVE, &value, &len)
        return Int(value)
    case JavaNetSocketOption.tcpNoDelay:
        var value: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        _ = getsockopt(box.fd, IPPROTO_TCP, TCP_NODELAY, &value, &len)
        return Int(value)
    case JavaNetSocketOption.soSndBuf:
        var value: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        _ = getsockopt(box.fd, SOL_SOCKET, SO_SNDBUF, &value, &len)
        return Int(value)
    case JavaNetSocketOption.soRcvBuf:
        var value: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        _ = getsockopt(box.fd, SOL_SOCKET, SO_RCVBUF, &value, &len)
        return Int(value)
    default:
        return 0
    }
}

@_cdecl("__kk_net_socket_set_option")
public func __kk_net_socket_set_option(_ boxRaw: Int, _ option: Int, _ value: Int) {
    guard let box = javaNetSocket(boxRaw) else { return }
    if box.fd < 0 { _ = box.ensureSocket(family: AF_INET) }
    guard box.fd >= 0 else { return }
    var intValue = Int32(truncatingIfNeeded: value)
    switch option {
    case JavaNetSocketOption.soTimeout:
        box.soTimeoutMillis = value
        var tv = timeval(tv_sec: value / 1000, tv_usec: __darwin_suseconds_t((value % 1000) * 1000))
        _ = setsockopt(box.fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    case JavaNetSocketOption.soReuseAddr:
        _ = setsockopt(box.fd, SOL_SOCKET, SO_REUSEADDR, &intValue, socklen_t(MemoryLayout<Int32>.size))
    case JavaNetSocketOption.soKeepAlive:
        _ = setsockopt(box.fd, SOL_SOCKET, SO_KEEPALIVE, &intValue, socklen_t(MemoryLayout<Int32>.size))
    case JavaNetSocketOption.tcpNoDelay:
        _ = setsockopt(box.fd, IPPROTO_TCP, TCP_NODELAY, &intValue, socklen_t(MemoryLayout<Int32>.size))
    case JavaNetSocketOption.soSndBuf:
        _ = setsockopt(box.fd, SOL_SOCKET, SO_SNDBUF, &intValue, socklen_t(MemoryLayout<Int32>.size))
    case JavaNetSocketOption.soRcvBuf:
        _ = setsockopt(box.fd, SOL_SOCKET, SO_RCVBUF, &intValue, socklen_t(MemoryLayout<Int32>.size))
    default:
        break
    }
}

@_cdecl("__kk_net_socket_shutdown")
public func __kk_net_socket_shutdown(_ boxRaw: Int, _ how: Int) {
    guard let box = javaNetSocket(boxRaw), box.fd >= 0 else { return }
    if how == 0 {
        shutdown(box.fd, SHUT_RD)
        box.inputShutdown = true
    } else {
        shutdown(box.fd, SHUT_WR)
        box.outputShutdown = true
    }
}

@_cdecl("__kk_net_socket_is_input_shutdown")
public func __kk_net_socket_is_input_shutdown(_ boxRaw: Int) -> Int {
    (javaNetSocket(boxRaw)?.inputShutdown ?? false) ? 1 : 0
}

@_cdecl("__kk_net_socket_is_output_shutdown")
public func __kk_net_socket_is_output_shutdown(_ boxRaw: Int) -> Int {
    (javaNetSocket(boxRaw)?.outputShutdown ?? false) ? 1 : 0
}

// MARK: - ServerSocket box

private final class RuntimeJavaNetServerSocketBox {
    var fd: Int32 = -1
    var bound = false
    var closed = false
    var soTimeoutMillis = 0
    var localPort = -1
    var localAddress: String?
}

private func javaNetServerSocket(_ raw: Int) -> RuntimeJavaNetServerSocketBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJavaNetServerSocketBox.self)
}

@_cdecl("__kk_net_server_socket_create")
public func __kk_net_server_socket_create() -> Int {
    registerRuntimeObject(RuntimeJavaNetServerSocketBox())
}

@_cdecl("__kk_net_server_socket_bind")
public func __kk_net_server_socket_bind(
    _ boxRaw: Int, _ hostRaw: Int, _ port: Int, _ backlog: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) {
    outThrown?.pointee = 0
    guard let box = javaNetServerSocket(boxRaw) else { return }
    if box.closed {
        outThrown?.pointee = runtimeAllocateSocketException("Socket is closed")
        return
    }
    let host = javaNetString(hostRaw) ?? "0.0.0.0"
    let targets = javaNetResolveSockaddr(host, port: port)
    guard let first = targets.first else {
        outThrown?.pointee = runtimeAllocateBindException("Can't assign requested address")
        return
    }
    var storage = first.addr
    if box.fd < 0 {
        box.fd = socket(Int32(storage.ss_family), SOCK_STREAM, 0)
    }
    guard box.fd >= 0 else {
        outThrown?.pointee = runtimeAllocateSocketException(javaNetErrorMessage(errno))
        return
    }
    var reuse: Int32 = 1
    _ = setsockopt(box.fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
    let bindResult = withUnsafePointer(to: &storage) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(box.fd, $0, first.len)
        }
    }
    if bindResult != 0 {
        let bindErrno = errno
        if bindErrno == EADDRINUSE {
            outThrown?.pointee = runtimeAllocateBindException("Address already in use")
        } else {
            outThrown?.pointee = runtimeAllocateBindException(javaNetErrorMessage(bindErrno))
        }
        return
    }
    if listen(box.fd, Int32(max(1, backlog))) != 0 {
        outThrown?.pointee = runtimeAllocateSocketException(javaNetErrorMessage(errno))
        return
    }
    box.bound = true
    var boundStorage = sockaddr_storage()
    var boundLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
    var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    var servBuffer = [CChar](repeating: 0, count: Int(NI_MAXSERV))
    _ = withUnsafeMutablePointer(to: &boundStorage) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(box.fd, $0, &boundLen) }
    }
    _ = withUnsafePointer(to: &boundStorage) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getnameinfo($0, boundLen, &hostBuffer, socklen_t(hostBuffer.count), &servBuffer, socklen_t(servBuffer.count), NI_NUMERICHOST | NI_NUMERICSERV)
        }
    }
    box.localAddress = javaNetNumericHost(String(cString: hostBuffer))
    box.localPort = Int(String(cString: servBuffer)) ?? port
}

@_cdecl("__kk_net_server_socket_accept")
public func __kk_net_server_socket_accept(_ boxRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let box = javaNetServerSocket(boxRaw), box.fd >= 0, !box.closed else {
        outThrown?.pointee = runtimeAllocateSocketException("Socket is closed")
        return 0
    }
    if box.soTimeoutMillis > 0 {
        var pollFd = pollfd(fd: box.fd, events: Int16(POLLIN), revents: 0)
        let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
        let ready = poll(&pollFd, 1, Int32(box.soTimeoutMillis))
        if gcBlocking { runtimeGCSafepoints.endBlocking() }
        if ready == 0 {
            outThrown?.pointee = runtimeAllocateSocketTimeoutException("Accept timed out")
            return 0
        }
        if ready < 0 {
            outThrown?.pointee = runtimeAllocateSocketException(javaNetErrorMessage(errno))
            return 0
        }
    }
    var peer = sockaddr_storage()
    var peerLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
    let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
    let clientFd = withUnsafeMutablePointer(to: &peer) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            accept(box.fd, $0, &peerLen)
        }
    }
    if gcBlocking { runtimeGCSafepoints.endBlocking() }
    guard clientFd >= 0 else {
        let acceptErrno = errno
        if acceptErrno == EAGAIN || acceptErrno == EWOULDBLOCK {
            outThrown?.pointee = runtimeAllocateSocketTimeoutException("Accept timed out")
        } else {
            outThrown?.pointee = runtimeAllocateSocketException(javaNetErrorMessage(acceptErrno))
        }
        return 0
    }
    let client = RuntimeJavaNetSocketBox()
    client.fd = clientFd
    client.connected = true
    client.bound = true
    var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    var servBuffer = [CChar](repeating: 0, count: Int(NI_MAXSERV))
    _ = withUnsafePointer(to: &peer) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getnameinfo($0, peerLen, &hostBuffer, socklen_t(hostBuffer.count), &servBuffer, socklen_t(servBuffer.count), NI_NUMERICHOST | NI_NUMERICSERV)
        }
    }
    client.remoteAddress = javaNetNumericHost(String(cString: hostBuffer))
    client.remotePort = Int(String(cString: servBuffer)) ?? -1
    client.refreshLocalPeer()
    return registerRuntimeObject(client)
}

@_cdecl("__kk_net_server_socket_close")
public func __kk_net_server_socket_close(_ boxRaw: Int) {
    guard let box = javaNetServerSocket(boxRaw), box.fd >= 0, !box.closed else { return }
    box.closed = true
    close(box.fd)
    box.fd = -1
}

@_cdecl("__kk_net_server_socket_is_closed")
public func __kk_net_server_socket_is_closed(_ boxRaw: Int) -> Int {
    (javaNetServerSocket(boxRaw)?.closed ?? true) ? 1 : 0
}

@_cdecl("__kk_net_server_socket_is_bound")
public func __kk_net_server_socket_is_bound(_ boxRaw: Int) -> Int {
    (javaNetServerSocket(boxRaw)?.bound ?? false) ? 1 : 0
}

@_cdecl("__kk_net_server_socket_local_port")
public func __kk_net_server_socket_local_port(_ boxRaw: Int) -> Int {
    javaNetServerSocket(boxRaw)?.localPort ?? -1
}

@_cdecl("__kk_net_server_socket_local_address")
public func __kk_net_server_socket_local_address(_ boxRaw: Int) -> Int {
    guard let address = javaNetServerSocket(boxRaw)?.localAddress else { return runtimeNullSentinelInt }
    return runtimeMakeUTF8StringRaw(address)
}

@_cdecl("__kk_net_server_socket_get_timeout")
public func __kk_net_server_socket_get_timeout(_ boxRaw: Int) -> Int {
    javaNetServerSocket(boxRaw)?.soTimeoutMillis ?? 0
}

@_cdecl("__kk_net_server_socket_set_timeout")
public func __kk_net_server_socket_set_timeout(_ boxRaw: Int, _ timeoutMillis: Int) {
    javaNetServerSocket(boxRaw)?.soTimeoutMillis = timeoutMillis
}

@_cdecl("__kk_net_server_socket_get_reuse_address")
public func __kk_net_server_socket_get_reuse_address(_ boxRaw: Int) -> Int {
    guard let box = javaNetServerSocket(boxRaw), box.fd >= 0 else { return 1 }
    var value: Int32 = 0
    var len = socklen_t(MemoryLayout<Int32>.size)
    _ = getsockopt(box.fd, SOL_SOCKET, SO_REUSEADDR, &value, &len)
    return Int(value)
}

@_cdecl("__kk_net_server_socket_set_reuse_address")
public func __kk_net_server_socket_set_reuse_address(_ boxRaw: Int, _ value: Int) {
    guard let box = javaNetServerSocket(boxRaw), box.fd >= 0 else { return }
    var intValue = Int32(truncatingIfNeeded: value)
    _ = setsockopt(box.fd, SOL_SOCKET, SO_REUSEADDR, &intValue, socklen_t(MemoryLayout<Int32>.size))
}
