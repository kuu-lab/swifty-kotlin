import Foundation

//
// Encode/decode/padding logic now lives in pure Kotlin
// (Sources/CompilerCore/Stdlib/kotlin/io/encoding/Base64.kt). Only the
// OutputStream.encodingWith stream wrapper stays as a runtime bridge, since it
// wraps a stateful native OutputStream sink that Kotlin has no direct handle to.

private func base64StringFromRaw(_ raw: Int) -> String? {
    if raw == runtimeNullSentinelInt { return nil }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return extractString(from: ptr)
}

final class RuntimeBase64EncodingOutputStreamSink: RuntimeOutputStreamSink {
    private let downstream: RuntimeOutputStreamBox
    private let alphabet: [UInt8]
    private let addPadding: Bool
    private var pending: [UInt8] = []

    init(downstream: RuntimeOutputStreamBox, alphabet: [UInt8], addPadding: Bool) {
        self.downstream = downstream
        self.alphabet = alphabet
        self.addPadding = addPadding
    }

    func write(_ data: Data) throws {
        let buf = pending + Array(data)
        var idx = 0
        var encoded: [UInt8] = []
        while idx + 2 < buf.count {
            let b0 = buf[idx]
            let b1 = buf[idx + 1]
            let b2 = buf[idx + 2]
            encoded.append(alphabet[Int(b0 >> 2)])
            encoded.append(alphabet[Int(((b0 & 0x03) << 4) | (b1 >> 4))])
            encoded.append(alphabet[Int(((b1 & 0x0F) << 2) | (b2 >> 6))])
            encoded.append(alphabet[Int(b2 & 0x3F)])
            idx += 3
        }
        pending = Array(buf[idx...])
        if !encoded.isEmpty {
            try downstream.write(Data(encoded))
        }
    }

    func flush() throws {
        if !pending.isEmpty {
            var encoded: [UInt8] = []
            let b0 = pending[0]
            if pending.count == 1 {
                encoded.append(alphabet[Int(b0 >> 2)])
                encoded.append(alphabet[Int((b0 & 0x03) << 4)])
                if addPadding { encoded += [0x3D, 0x3D] } // ==
            } else {
                let b1 = pending[1]
                encoded.append(alphabet[Int(b0 >> 2)])
                encoded.append(alphabet[Int(((b0 & 0x03) << 4) | (b1 >> 4))])
                encoded.append(alphabet[Int((b1 & 0x0F) << 2)])
                if addPadding { encoded.append(0x3D) } // =
            }
            pending = []
            try downstream.write(Data(encoded))
        }
        try downstream.flush()
    }

    func close() {
        // Best-effort flush; ignore errors on close
        try? flush()
        downstream.close()
    }
}

private func makeBase64EncodingOutputStream(
    from streamRaw: Int,
    alphabet: [UInt8],
    addPadding: Bool
) -> RuntimeOutputStreamBox? {
    guard let downstream = runtimeOutputStreamBox(from: streamRaw) else {
        return nil
    }
    let sink = RuntimeBase64EncodingOutputStreamSink(
        downstream: downstream,
        alphabet: alphabet,
        addPadding: addPadding
    )
    return RuntimeOutputStreamBox(sink: sink)
}

/// The alphabet and padding decision are computed Kotlin-side (from the
/// `Base64` instance's `alphabetChars`) and passed as primitives, since the
/// `Base64` instance itself is now a plain Kotlin object with no Swift-side
/// boxed representation.
@_cdecl("__kk_output_stream_encodingWith")
public func kk_output_stream_encodingWith(_ streamRaw: Int, _ alphabetRaw: Int, _ addPaddingRaw: Int) -> Int {
    let alphabet = Array((base64StringFromRaw(alphabetRaw) ?? "").utf8)
    let addPadding = addPaddingRaw != 0
    guard let encodingStream = makeBase64EncodingOutputStream(
        from: streamRaw,
        alphabet: alphabet,
        addPadding: addPadding
    ) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_output_stream_encodingWith received invalid OutputStream handle")
    }
    return runtimeRegisterIoStream(encodingStream, fqName: "java.io.OutputStream", input: false)
}
