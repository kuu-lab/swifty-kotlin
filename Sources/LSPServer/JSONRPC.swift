import Foundation

/// A source of bytes for the language server's input stream.
/// `readChunk()` blocks until at least one byte is available and returns an
/// empty `Data` to signal end of stream.
public protocol ByteInputStream: AnyObject {
    func readChunk() -> Data
}

/// A sink of bytes for the language server's output stream.
public protocol ByteOutputStream: AnyObject {
    func write(_ data: Data)
}

/// Reads the process's standard input in blocking chunks.
public final class StandardInputStream: ByteInputStream {
    private let handle: FileHandle

    public init(handle: FileHandle = .standardInput) {
        self.handle = handle
    }

    public func readChunk() -> Data {
        handle.availableData
    }
}

/// Writes to the process's standard output, serializing concurrent writes.
public final class StandardOutputStream: ByteOutputStream {
    private let handle: FileHandle
    private let lock = NSLock()

    public init(handle: FileHandle = .standardOutput) {
        self.handle = handle
    }

    public func write(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        handle.write(data)
    }
}

/// Minimal JSON-RPC 2.0 transport over a byte stream using the LSP base
/// protocol framing (`Content-Length: N\r\n\r\n` followed by `N` body bytes).
///
/// Messages are exchanged as loosely-typed JSON objects (`[String: Any]`).
/// Typed payloads are bridged via `JSONCoding`.
public final class JSONRPCConnection {
    /// Default upper bound on a single message body (32 MiB). Frames declaring a
    /// larger `Content-Length` are rejected to prevent memory-exhaustion DoS.
    public static let defaultMaxBodyBytes = 32 * 1024 * 1024

    /// Default upper bound on the header block scanned for the `\r\n\r\n`
    /// terminator (64 KiB). Prevents unbounded buffering when a peer never
    /// sends the terminator.
    public static let defaultMaxHeaderBytes = 64 * 1024

    private let input: ByteInputStream
    private let output: ByteOutputStream
    private var buffer = Data()
    private let maxBodyBytes: Int
    private let maxHeaderBytes: Int

    public init(
        input: ByteInputStream,
        output: ByteOutputStream,
        maxBodyBytes: Int = JSONRPCConnection.defaultMaxBodyBytes,
        maxHeaderBytes: Int = JSONRPCConnection.defaultMaxHeaderBytes
    ) {
        self.input = input
        self.output = output
        self.maxBodyBytes = maxBodyBytes
        self.maxHeaderBytes = maxHeaderBytes
    }

    /// Reads and decodes the next framed message. Returns `nil` at end of
    /// stream. Malformed frames are skipped.
    public func receive() -> [String: Any]? {
        while true {
            guard let headerOffset = indexOfHeaderTerminator() else {
                // No terminator yet. Guard against a peer that never sends
                // `\r\n\r\n` by refusing to buffer an unbounded header block.
                if buffer.count > maxHeaderBytes {
                    buffer.removeAll(keepingCapacity: false)
                    return nil
                }
                if !readMore() { return nil }
                continue
            }

            let headerData = Data(buffer.prefix(headerOffset))
            guard let contentLength = parseContentLength(headerData),
                  contentLength >= 0,
                  contentLength <= maxBodyBytes
            else {
                // Missing, malformed, negative, or oversized Content-Length:
                // drop the header block and resynchronize.
                buffer = Data(buffer.dropFirst(headerOffset + 4))
                continue
            }

            let bodyStart = headerOffset + 4
            let (totalNeeded, overflowed) = bodyStart.addingReportingOverflow(contentLength)
            if overflowed {
                buffer = Data(buffer.dropFirst(bodyStart))
                continue
            }
            while buffer.count < totalNeeded {
                if !readMore() { return nil }
            }

            let bodyData = Data(buffer.dropFirst(bodyStart).prefix(contentLength))
            buffer = Data(buffer.dropFirst(totalNeeded))

            if let object = try? JSONSerialization.jsonObject(with: bodyData),
               let dict = object as? [String: Any]
            {
                return dict
            }
            // Malformed body: skip and continue reading.
        }
    }

    /// Frames and writes a message object.
    public func send(_ message: [String: Any]) {
        guard let body = try? JSONSerialization.data(
            withJSONObject: message,
            options: [.sortedKeys]
        ) else {
            return
        }
        var framed = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        framed.append(body)
        output.write(framed)
    }

    // MARK: - Framing helpers

    private func readMore() -> Bool {
        let chunk = input.readChunk()
        if chunk.isEmpty { return false }
        buffer.append(chunk)
        return true
    }

    /// Returns the offset of the first `\r\n\r\n` sequence, or `nil` if absent.
    private func indexOfHeaderTerminator() -> Int? {
        buffer.withUnsafeBytes { raw -> Int? in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard bytes.count >= 4 else { return nil }
            var i = 0
            let end = bytes.count - 3
            while i < end {
                if bytes[i] == 0x0D, bytes[i + 1] == 0x0A, bytes[i + 2] == 0x0D, bytes[i + 3] == 0x0A {
                    return i
                }
                i += 1
            }
            return nil
        }
    }

    private func parseContentLength(_ headerData: Data) -> Int? {
        let text = String(decoding: headerData, as: UTF8.self)
        for rawLine in text.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) {
            let parts = rawLine.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            if name == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }
}

/// Bridges `Codable` payloads and the loosely-typed JSON objects exchanged by
/// `JSONRPCConnection`.
public enum JSONCoding {
    /// Encodes a value into a JSON object/array/scalar suitable for embedding in
    /// a message dictionary.
    public static func toObject(_ value: some Encodable) -> Any? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Decodes a typed value from a JSON object previously produced by
    /// `JSONSerialization`.
    public static func decode<T: Decodable>(_ type: T.Type, from object: Any) -> T? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.fragmentsAllowed]
        ) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}
