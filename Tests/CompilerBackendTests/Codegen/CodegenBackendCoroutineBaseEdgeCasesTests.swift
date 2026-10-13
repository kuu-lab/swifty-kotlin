#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCoroutineBaseEdgeCasesTests {

    @Test(arguments: [true, false])
    func testSchedulerClockUsesLongABI(useArtifact: Bool) throws {
        let source = """
        import kotlinx.coroutines.test.*

        fun main() {
            val scope = TestScope()
            val scheduler = scope.testScheduler
            scheduler.advanceTimeBy(4294967297L)
            println(scheduler.currentTime)
            println(scope.currentTime)
            scope.advanceTimeBy(2L)
            println(scheduler.currentTime)
            println(scope.currentTime)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "TestSchedulerLongABI",
            expected: "4294967297\n4294967297\n4294967299\n4294967299\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}
#endif
