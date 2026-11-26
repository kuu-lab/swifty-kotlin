import Foundation

/// `readChunk()` blocks until at least one byte is available and returns an
/// empty `Data` to signal end of stream.
public protocol ByteInputStream: AnyObject {
    func readChunk() -> Data
}

public protocol ByteOutputStream: AnyObject {
    func write(_ data: Data)
}

public final class StandardInputStream: ByteInputStream {
    private let handle: FileHandle

    public init(handle: FileHandle = .standardInput) {
        self.handle = handle
    }

    public func readChunk() -> Data {
        handle.availableData
    }
}

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

public final class JSONRPCConnection {
    public static let defaultMaxBodyBytes = 32 * 1024 * 1024

    public static let defaultMaxHeaderBytes = 64 * 1024

    private let input: ByteInputStream
    private let output: ByteOutputStream
    private let sendLock = NSLock()
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

    /// Returns `nil` at end of stream. Malformed frames are skipped.
    public func receive() -> [String: Any]? {
        while true {
            guard let headerOffset = indexOfHeaderTerminator() else {
                if buffer.count > maxHeaderBytes {
                    buffer.removeAll(keepingCapacity: false)
                    return nil
                }
                if !readMore() { return nil }
                continue
            }

            let headerData = Data(buffer.prefix(headerOffset))
            guard let contentLength = parseContentLength(headerData) else {
                buffer = Data(buffer.dropFirst(headerOffset + 4))
                continue
            }

            if contentLength < 0 {
                buffer = Data(buffer.dropFirst(headerOffset + 4))
                continue
            }

            if contentLength > maxBodyBytes {
                if !discard(headerOffset + 4) { return nil }
                if !discard(contentLength) { return nil }
                continue
            }

            let bodyStart = headerOffset + 4
            let (totalNeeded, overflowed) = bodyStart.addingReportingOverflow(contentLength)
            if overflowed {
                return nil
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
        }
    }

    public func send(_ message: [String: Any]) {
        guard let body = try? JSONSerialization.data(
            withJSONObject: message,
            options: [.sortedKeys]
        ) else {
            return
        }
        var framed = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        framed.append(body)

        sendLock.lock()
        defer { sendLock.unlock() }
        output.write(framed)
    }

    private func readMore() -> Bool {
        let chunk = input.readChunk()
        if chunk.isEmpty { return false }
        buffer.append(chunk)
        return true
    }

    private func discard(_ count: Int) -> Bool {
        var remaining = count
        while remaining > 0 {
            if buffer.isEmpty {
                if !readMore() { return false }
                continue
            }

            let toDrop = min(remaining, buffer.count)
            buffer.removeFirst(toDrop)
            remaining -= toDrop
        }
        return true
    }

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

public enum JSONCoding {
    public static func toObject(_ value: some Encodable) -> Any? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

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
