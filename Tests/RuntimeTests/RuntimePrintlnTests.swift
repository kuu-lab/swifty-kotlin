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

    private func makeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
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
