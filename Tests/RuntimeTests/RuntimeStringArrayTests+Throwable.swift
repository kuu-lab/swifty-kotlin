#if canImport(Testing)
@testable import Runtime
import Testing
import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

extension RuntimeStringArrayTests {
    private func captureStandardError(_ block: () -> Void) -> String {
        let pipe = Pipe()
        let savedFD = dup(STDERR_FILENO)
        fflush(nil)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        block()
        fflush(nil)
        dup2(savedFD, STDERR_FILENO)
        close(savedFD)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }


    // MARK: - __kk_throwable_new

    @Test
    func testThrowableNewCreatesThrowable() {
        let msg = makeRuntimeString("error occurred")
        let throwable = __kk_throwable_new(msg)
        #expect(throwable as UnsafeMutableRawPointer? != nil)
        let output = capturePrintln { kk_println_any(throwable) }
        #expect(output.contains("error occurred"))
    }

    @Test
    func testThrowableNewWithNilUsesDefaultMessage() {
        let throwable = __kk_throwable_new(nil)
        #expect(throwable as UnsafeMutableRawPointer? != nil)
        #expect(__kk_throwable_message(Int(bitPattern: throwable)) == runtimeNullSentinelInt)
        let output = capturePrintln { kk_println_any(throwable) }
        #expect(output.contains("Throwable"))
    }

    @Test
    func testThrowableNewCauseUsesCauseToStringAndPreservesCause() {
        let cause = Int(bitPattern: __kk_throwable_new(makeRuntimeString("root cause")))
        let throwable = Int(bitPattern: __kk_throwable_new_cause(cause))

        #expect(runtimeTestStringValue(__kk_throwable_message(throwable)) == "java.lang.Throwable: root cause")
        #expect(__kk_throwable_cause(throwable) == cause)
    }

    @Test
    func testThrowableNewCauseWithNilPreservesNullMessageAndCause() {
        let causeOnly = Int(bitPattern: __kk_throwable_new_cause(runtimeNullSentinelInt))
        let messageCause = Int(bitPattern: __kk_throwable_new_with_cause(nil, runtimeNullSentinelInt))

        for throwable in [causeOnly, messageCause] {
            #expect(__kk_throwable_message(throwable) == runtimeNullSentinelInt)
            #expect(__kk_throwable_cause(throwable) == runtimeNullSentinelInt)
        }
    }

    /// Runtime-allocated throwables have no Kotlin vtable; the open `message`
    /// and `cause` getter slots must resolve to raw-ABI runtime bridges.
    @Test
    func testThrowableVtableLookupResolvesMessageAndCauseSlots() {
        let cause = Int(bitPattern: __kk_throwable_new(makeRuntimeString("inner")))
        let throwable = Int(bitPattern: __kk_throwable_new_with_cause(makeRuntimeString("outer"), cause))
        typealias Getter = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

        let messageGetter = unsafeBitCast(
            kk_vtable_lookup(throwable, RuntimeThrowableVtableSlot.message),
            to: Getter.self
        )
        var thrown = -1
        #expect(runtimeTestStringValue(messageGetter(throwable, &thrown)) == "outer")
        #expect(thrown == 0)

        let causeGetter = unsafeBitCast(
            kk_vtable_lookup(throwable, RuntimeThrowableVtableSlot.cause),
            to: Getter.self
        )
        #expect(causeGetter(throwable, nil) == cause)

        let noMessage = Int(bitPattern: __kk_throwable_new(nil))
        #expect(messageGetter(noMessage, nil) == runtimeNullSentinelInt)
    }

    @Test
    func testThrowableIsCancellationReturnsFalseForNil() {
        #expect(kk_throwable_is_cancellation(0) == 0)
    }

    @Test
    func testThrowableIsCancellationReturnsFalseForRegularThrowable() {
        let throwable = __kk_throwable_new(makeRuntimeString("not cancellation"))
        let raw = Int(bitPattern: throwable)
        #expect(kk_throwable_is_cancellation(raw) == 0)
    }

    @Test
    func testThrowableAddSuppressedPreservesInsertionOrder() {
        let primary = Int(bitPattern: __kk_throwable_new(makeRuntimeString("primary")))
        let suppressed1 = Int(bitPattern: __kk_throwable_new(makeRuntimeString("suppressed1")))
        let suppressed2 = Int(bitPattern: __kk_throwable_new(makeRuntimeString("suppressed2")))

        _ = __kk_throwable_appendSuppressed(primary, suppressed1)
        _ = __kk_throwable_appendSuppressed(primary, suppressed2)

        let suppressed = __kk_throwable_suppressedRaw(primary)
        #expect(kk_array_size(suppressed) == 2)

        var thrown = 0
        #expect(kk_array_get(suppressed, 0, &thrown) == suppressed1)
        #expect(thrown == 0)
        #expect(kk_array_get(suppressed, 1, &thrown) == suppressed2)
        #expect(thrown == 0)
    }

    @Test
    func testThrowableAddSuppressedRejectsSelfSuppression() {
        let primary = Int(bitPattern: __kk_throwable_new(makeRuntimeString("primary")))

        _ = __kk_throwable_appendSuppressed(primary, primary)

        let suppressed = __kk_throwable_suppressedRaw(primary)
        #expect(kk_array_size(suppressed) == 0)
    }

    @Test
    func testThrowableAddSuppressedIgnoresNullAndInvalidHandles() {
        let primary = Int(bitPattern: __kk_throwable_new(makeRuntimeString("primary")))

        _ = __kk_throwable_appendSuppressed(primary, runtimeNullSentinelInt)
        _ = __kk_throwable_appendSuppressed(primary, 0)
        _ = __kk_throwable_appendSuppressed(primary, 123456789)
        _ = __kk_throwable_appendSuppressed(runtimeNullSentinelInt, primary)
        _ = __kk_throwable_appendSuppressed(123456789, primary)

        let suppressed = __kk_throwable_suppressedRaw(primary)
        #expect(kk_array_size(suppressed) == 0)
    }

    @Test
    func testThrowableRawStackFramesReturnsQualifiedHeaderAndSavedFrames() throws {
        let throwable = Int(bitPattern: __kk_throwable_new(makeRuntimeString("print me")))

        let frames = __kk_throwable_rawStackFrames(throwable)
        let box = try #require(throwableBox(from: throwable))
        #expect(kk_array_size(frames) == box.stackTraceAddresses.count + 1)

        var thrown = 0
        let frameRaw = kk_array_get(frames, 0, &thrown)
        #expect(thrown == 0)
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: frameRaw)) == "java.lang.Throwable: print me")
        let savedLines = runtimeThrowableStackFrameLines(box.stackTraceAddresses)
        #expect(!savedLines.isEmpty)
        for (index, savedLine) in savedLines.enumerated() {
            let raw = kk_array_get(frames, index + 1, &thrown)
            #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) == savedLine)
            #expect(savedLine.hasPrefix("\tat "))
        }
    }

    @Test
    func testPrintStderrWritesMessageToStandardError() {
        let message = rawFromRuntimeString("print me")

        let output = captureStandardError {
            #expect(__kk_printStderr(message) == 0)
        }

        #expect(output == "print me")
    }
}
#endif
