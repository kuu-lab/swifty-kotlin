import Foundation

#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc

// Glibc's Swift module does not expose execinfo.h.
@_silgen_name("backtrace_symbols")
private func backtrace_symbols(
    _ addresses: UnsafePointer<UnsafeMutableRawPointer?>,
    _ count: Int32
) -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
#endif

/// Symbolicate the addresses saved at construction, never the formatting call's
/// stack. Native symbols can include runtime frames and mangled Kotlin names;
/// stripped binaries still retain an address for each frame.
func runtimeThrowableStackFrameLines(_ addresses: [Int]) -> [String] {
    guard !addresses.isEmpty else { return [] }
    let pointers = addresses.map { UnsafeMutableRawPointer(bitPattern: $0) }
#if os(macOS) || os(Linux)
    let symbols = pointers.withUnsafeBufferPointer { buffer in
        backtrace_symbols(buffer.baseAddress!, Int32(buffer.count))
    }
    if let symbols {
        defer { free(symbols) }
        return addresses.indices.map { index in
            let frame = symbols[index].map { String(cString: $0) }
                ?? "0x" + String(UInt(bitPattern: addresses[index]), radix: 16)
            return "\tat " + frame
        }
    }
#endif
    return addresses.map { "\tat 0x" + String(UInt(bitPattern: $0), radix: 16) }
}
