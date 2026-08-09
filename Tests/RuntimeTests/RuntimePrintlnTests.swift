@testable import Runtime
import Foundation
import Testing

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimePrintlnTests {
    private func capturePrintln(_ block: () -> Void) -> String {
        let pipe = Pipe()
        let savedFD = dup(STDOUT_FILENO)
        fflush(nil)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        block()
        fflush(nil)
        dup2(savedFD, STDOUT_FILENO)
        close(savedFD)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    @Test func printlnNilPrintsZero() {
        let output = capturePrintln { kk_println_any(nil) }
        #expect(output == "0")
    }

    @Test func printlnNullSentinelPrintsNull() {
        let sentinel = UnsafeMutableRawPointer(bitPattern: Int(Int64.min))
        let output = capturePrintln { kk_println_any(sentinel) }
        #expect(output == "null")
    }

    @Test func printlnSmallIntPrintsValue() {
        let ptr = UnsafeMutableRawPointer(bitPattern: 42)
        let output = capturePrintln { kk_println_any(ptr) }
        #expect(output == "42")
    }

    @Test func printlnLongPrintsValue() {
        let output = capturePrintln { kk_println_long(123_456_789) }
        #expect(output == "123456789")
    }

    @Test func printlnDoubleDecodesBitPattern() {
        let output = capturePrintln { kk_println_double(kk_double_to_bits(2.5)) }
        #expect(output == "2.5")
    }

    @Test func printlnCharPrintsUnicodeScalar() {
        let output = capturePrintln { kk_println_char(0x41) }
        #expect(output == "A")
    }

    @Test func printlnCharSurrogatePrintsQuestionMark() {
        let output = capturePrintln { kk_println_char(0xDF1F) }
        #expect(output == "?")
    }

    @Test func printlnBoxedCharSurrogatePrintsQuestionMark() {
        let output = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: kk_box_char(0xDF1F))) }
        #expect(output == "?")
    }

    @Test func notImplementedErrorNoArgUsesDefaultMessage() {
        let thrown = __kk_not_implemented_error_new()
        let rendered = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        #expect(rendered == "Throwable(NotImplementedError: An operation is not implemented.)")
    }

    @Test func notImplementedErrorWithMessageUsesGivenMessage() {
        let message = "An operation is not implemented: later"
        let messageRaw = message.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: message.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(message.utf8.count)))
            }
        }
        let thrown = __kk_not_implemented_error_new_message(messageRaw)
        let rendered = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        #expect(rendered == "Throwable(NotImplementedError: An operation is not implemented: later)")
    }
}
