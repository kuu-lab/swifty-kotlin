#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendJavaIOStreamExceptionTests {

    @Test func testStreamIOFailureIsCaughtAsExceptionAndIOException() throws {
        let source = """
        import java.io.ByteArrayInputStream
        import java.io.IOException

        fun main() {
            try {
                val stream = ByteArrayInputStream(listOf(1))
                stream.reset()
                println("not caught")
            } catch (e: Exception) {
                println("caught Exception")
            } catch (e: Throwable) {
                println("wrong Throwable")
            }

            try {
                val stream = ByteArrayInputStream(listOf(1))
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
