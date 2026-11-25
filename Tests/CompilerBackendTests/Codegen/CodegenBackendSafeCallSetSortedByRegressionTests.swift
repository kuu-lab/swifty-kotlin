#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSafeCallSetSortedByRegressionTests {

    @Test
    func testCodegenSetSortedByDirectCall() throws {
        let source = """
        fun main() {
            val m = mapOf("b" to "2", "a" to "1")
            val sorted = m.entries.sortedBy { it.key }
            println(sorted.joinToString(",") { "${it.key}=${it.value}" })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SetSortedByDirect",
            expected: "a=1,b=2\n"
        )
    }

    // `sortedBy` itself now runs through the real safe-call chain
    // (`holder?.options?.entries?.sortedBy { ... }`), exercising the KIR
    // fixes above end to end. The `joinToString` call afterwards is guarded
    // by an explicit null check (rather than `?.`) to route around the
    // separate, still-open Sema gap described above.
    @Test
    func testCodegenSetSortedByThroughSafeCallChain() throws {
        let source = """
        data class Holder(val options: Map<String, String>)

        fun main() {
            val holder: Holder? = Holder(mapOf("b" to "2", "a" to "1"))
            val sorted = holder?.options?.entries?.sortedBy { it.key }
            if (sorted != null) {
                println(sorted.joinToString(",") { "${it.key}=${it.value}" })
            } else {
                println("null")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SetSortedBySafeCallChain",
            expected: "a=1,b=2\n"
        )
    }

    @Test
    func testCodegenSetSortedByInsideSafeCallLet() throws {
        let source = """
        data class Holder(val options: Map<String, String>)

        fun main() {
            val holder: Holder? = Holder(mapOf("b" to "2", "a" to "1"))
            val summary = holder?.options?.entries?.let { entries ->
                entries.sortedBy { it.key }.joinToString(",") { "${it.key}=${it.value}" }
            }
            println("options=$summary")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SetSortedBySafeCallLet",
            expected: "options=a=1,b=2\n"
        )
    }
}
#endif
