import Foundation
import RuntimeCAtomics
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Uses stdio's input buffer, shared with Swift.readLine(), so console and
/// stream reads advance the same cursor. Construction performs no input reads.
final class RuntimeStdioInputStreamBox: RuntimeInputStreamBox {
    private var stream: UnsafeMutablePointer<FILE>?
    private var failure: String?

    override var readError: String? { failure }

    init(stream: UnsafeMutablePointer<FILE>) {
        self.stream = stream
        super.init(data: Data())
    }

    override func readByte() -> Int {
        failure = nil
        guard let stream else {
            failure = "Stream Closed"
            return -1
        }
        while true {
            let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
            let value = fgetc(stream)
            let readErrno = errno
            let hasError = value == EOF && ferror(stream) != 0
            if gcBlocking { runtimeGCSafepoints.endBlocking() }
            if hasError {
                if readErrno == EINTR {
                    clearerr(stream)
                    continue
                }
                failure = String(cString: strerror(readErrno))
            }
            return Int(value)
        }
    }

    override func available() -> Int {
        // Zero is a conservative non-blocking estimate for an arbitrary stdin.
        0
    }

    override func skip(_ count: Int) -> Int {
        failure = nil
        var skipped = 0
        while skipped < count, readByte() != -1 {
            skipped += 1
        }
        return skipped
    }

    override func readAllBytes() -> [Int] {
        var bytes: [Int] = []
        while true {
            let byte = readByte()
            guard byte != -1 else { return bytes }
            bytes.append(Int(Int8(bitPattern: UInt8(byte))))
        }
    }

    func drainRemaining() -> Data {
        Data(readAllBytes().map { UInt8(truncatingIfNeeded: $0) })
    }

    override func close() {
        guard let stream else { return }
        self.stream = nil
        fclose(stream)
    }
}

@_cdecl("__kk_system_in")
public func __kk_system_in() -> Int {
    runtimeRegisterIoStream(
        RuntimeStdioInputStreamBox(stream: kkrt_standard_input()),
        fqName: "java.io.InputStream",
        input: true
    )
}

func runtimePropagateInputStreamError(
    _ stream: RuntimeInputStreamBox,
    _ outThrown: UnsafeMutablePointer<Int>?
) {
    if let message = stream.readError {
        outThrown?.pointee = runtimeAllocateIOException(message: message)
    }
}
