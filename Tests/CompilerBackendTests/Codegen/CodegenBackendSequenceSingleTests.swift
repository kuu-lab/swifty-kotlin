@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendSequenceSingleTests {

    @Test
    func codegenSequenceSingleUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("sequence_single.kt")

        try assertKotlinOutput(
            source,
            moduleName: "SequenceSingle",
            expected:
                """
                42
                only
                """
                + "\n"
        )
    }

    @Test
    func codegenSequenceSingleThrowsTypedExceptionsForInvalidCardinality() throws {
        let source = """
        fun main() {
            try {
                sequenceOf(1, 2).single()
                println("missing-multiple")
            } catch (e: IllegalArgumentException) {
                println("multiple: IAE")
            } catch (e: NoSuchElementException) {
                println("multiple: NSE")
            } catch (e: Exception) {
                println("multiple: Exception")
            } catch (e: Throwable) {
                println("multiple: Throwable")
            }

            try {
                emptySequence<Int>().single()
                println("missing-empty")
            } catch (e: IllegalArgumentException) {
                println("empty: IAE")
            } catch (e: NoSuchElementException) {
                println("empty: NSE")
            } catch (e: Exception) {
                println("empty: Exception")
            } catch (e: Throwable) {
                println("empty: Throwable")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceSingleTypedExceptions",
            expected: "multiple: IAE\nempty: NSE\n"
        )
    }
}
#endif
