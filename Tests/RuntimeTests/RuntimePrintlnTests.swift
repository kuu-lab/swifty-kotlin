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
    private func capturePrintln(fileDescriptor: Int32 = STDOUT_FILENO, _ block: () -> Void) -> String {
        let pipe = Pipe()
        let savedFD = dup(fileDescriptor)
        fflush(nil)
        dup2(pipe.fileHandleForWriting.fileDescriptor, fileDescriptor)
        block()
        fflush(nil)
        dup2(savedFD, fileDescriptor)
        close(savedFD)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func makeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    @Test func consoleBridgesReplaceIsolatedSurrogates() {
        let value = runtimeMakeStringRaw(runtimeKotlinStringFromUTF16CodeUnits(
            [0xD800, 0xD83C, 0xDF1F, 0xDC00, 0xFFFD]
        ))
        #expect(capturePrintln { __kk_print_raw(value) } == "?🌟?\u{FFFD}")
        #expect(capturePrintln { __kk_println_raw(value) } == "?🌟?\u{FFFD}")
        #expect(capturePrintln(fileDescriptor: STDERR_FILENO) {
            _ = __kk_printStderr(value)
        } == "?🌟?\u{FFFD}")
        #expect(runtimeStringUTF16CodeUnits(value) == [0xD800, 0xD83C, 0xDF1F, 0xDC00, 0xFFFD])
    }

    @Test func printRawWritesStringWithoutNewline() {
        let output = capturePrintln {
            __kk_print_raw(makeStringRaw("hello"))
            __kk_print_raw(makeStringRaw(" "))
            __kk_print_raw(makeStringRaw("world"))
            __kk_print_raw(makeStringRaw("\n"))
        }
        #expect(output == "hello world")
    }

    @Test func printRawNullSentinelPrintsNull() {
        let output = capturePrintln {
            __kk_print_raw(runtimeNullSentinelInt)
            __kk_print_raw(makeStringRaw("\n"))
        }
        #expect(output == "null")
    }

    @Test func printRawEmptyStringPrintsNothing() {
        let output = capturePrintln {
            __kk_print_raw(makeStringRaw(""))
            __kk_print_raw(makeStringRaw("\n"))
        }
        #expect(output == "")
    }
}
