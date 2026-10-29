@testable import CompilerCore
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendContextCompoundAssignmentTests {
    @Test
    func testContextPlusAssignReceivesImplicitContextOnLocalTarget() throws {
        let source = """
        class R(var i: Int)
        context(c: Int)
        operator fun R.plusAssign(o: R) { i += o.i + c }
        fun main() {
            val r = R(0)
            with(5) { r += R(1) }
            println(r.i)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KUU3276ContextPlusAssignLocal",
            expected: "6\n"
        )
    }

    @Test
    func testContextPlusAssignReceivesImplicitContextOnIndexedElement() throws {
        let source = """
        class R(var i: Int)
        context(c: Int)
        operator fun R.plusAssign(o: R) { i += o.i + c }
        class CellArray(val item: R) {
            operator fun get(index: Int): R = item
        }
        fun main() {
            val values = CellArray(R(0))
            with(5) { values[0] += R(1) }
            println(values[0].i)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KUU3276ContextPlusAssignIndexed",
            expected: "6\n"
        )
    }
}
#endif
