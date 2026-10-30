#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendJavaIOStreamExceptionTests {

    @Test func testStreamIOFailureIsCaughtAsExceptionAndIOException() throws {
        // `SequenceInputStream` does not support mark/reset, so `reset()`
        // throws `IOException` exactly like the JVM — the exception must be
        // catchable through both the `Exception` and `IOException` supertypes.
        let source = """
        import java.io.SequenceInputStream
        import java.io.IOException

        fun main() {
            try {
                val stream = SequenceInputStream("a".byteInputStream(), "b".byteInputStream())
                stream.mark(1)
                stream.reset()
                println("not caught")
            } catch (e: Exception) {
                println("caught Exception")
            } catch (e: Throwable) {
                println("wrong Throwable")
            }

            try {
                val stream = SequenceInputStream("a".byteInputStream(), "b".byteInputStream())
                stream.mark(1)
                stream.reset()
                println("not caught")
            } catch (e: IOException) {
                println("caught IOException")
            } catch (e: Exception) {
                println("caught Exception instead")
            } catch (e: Throwable) {
                println("wrong Throwable")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "JavaIOStreamException",
            expected: "caught Exception\ncaught IOException\n"
        )
    }
}
#endif
