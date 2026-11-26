#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCoroutineCancellationEdgeCasesTests {


    @Test func testTimeoutOrNullUnitResultPreservesNullFromStdlibSource() throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            println(withTimeoutOrNull(1) { delay(5000) })
            val expired = withTimeoutOrNull(1L) { delay(5000) }
            println(expired == null)
            val erased: Any? = expired
            println(erased)
            println("result=$expired")
            println(withTimeoutOrNull(5000) { delay(1) })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TimeoutOrNullUnitBoxingSource",
            expected: """
            null
            true
            null
            result=null
            kotlin.Unit

            """,
            allowDefaultStdlibLibrary: false
        )
    }


}
#endif
