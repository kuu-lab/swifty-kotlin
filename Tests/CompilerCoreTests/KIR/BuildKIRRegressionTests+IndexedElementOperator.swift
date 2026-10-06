#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    // Regression coverage for `a[i] op= v` / `a[i]++` whose element type
    // defines its own operator. Lowering used to always emit the builtin
    // `kk_op_*` arithmetic on the element (panicking or failing Sema for
    // class elements), and evaluated the right-hand side before `get()`.

    /// Callees of `main` starting at the compound assignment's element read;
    /// `arrayOf(...)` itself fills the array with `kk_array_set` beforehand.
    private func mainCallees(_ source: String) throws -> [String] {
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        let readIndex = try #require(callees.firstIndex(of: "kk_array_get"), "got: \(callees)")
        return Array(callees[readIndex...])
    }

    @Test func testIndexedCompoundAssignCallsElementPlusOperator() throws {
        let callees = try mainCallees("""
        class V(val x: Int) { operator fun plus(o: V) = V(x + o.x) }
        fun main() {
            val a = arrayOf(V(1))
            a[0] += V(2)
        }
        """)
        let getIndex = try #require(callees.firstIndex(of: "kk_array_get"), "got: \(callees)")
        let plusIndex = try #require(callees.firstIndex(of: "plus"), "Expected V.plus, got: \(callees)")
        let setIndex = try #require(callees.firstIndex(of: "kk_array_set"), "got: \(callees)")
        #expect(getIndex < plusIndex && plusIndex < setIndex, "got: \(callees)")
        #expect(!callees.contains("kk_op_add"), "The builtin add must not be applied to a class element, got: \(callees)")
    }

    @Test func testIndexedPlusAssignElementOperatorSkipsWriteBack() throws {
        let callees = try mainCallees("""
        class Acc { var s = 0; operator fun plusAssign(n: Int) { s += n } }
        fun main() {
            val a = arrayOf(Acc())
            a[0] += 5
        }
        """)
        #expect(callees.contains("plusAssign"), "Expected Acc.plusAssign, got: \(callees)")
        #expect(!callees.contains("kk_array_set"), "An in-place plusAssign must not write the element back, got: \(callees)")
    }

    @Test func testIndexedIncrementCallsElementIncOperator() throws {
        let callees = try mainCallees("""
        class C(val n: Int) { operator fun inc() = C(n + 1) }
        fun main() {
            val a = arrayOf(C(1))
            a[0]++
        }
        """)
        let incIndex = try #require(callees.firstIndex(of: "inc"), "Expected C.inc, got: \(callees)")
        let setIndex = try #require(callees.firstIndex(of: "kk_array_set"), "got: \(callees)")
        #expect(incIndex < setIndex, "got: \(callees)")
        #expect(!callees.contains("kk_op_add"), "got: \(callees)")
    }

    @Test func testIndexedCompoundAssignReadsElementBeforeRightHandSide() throws {
        let callees = try mainCallees("""
        fun v(): Int = 1
        fun main() {
            val a = intArrayOf(10)
            a[0] += v()
        }
        """)
        let getIndex = try #require(callees.firstIndex(of: "kk_array_get"), "got: \(callees)")
        let valueIndex = try #require(callees.firstIndex(of: "v"), "got: \(callees)")
        #expect(getIndex < valueIndex, "Kotlin evaluates get() before the right-hand side, got: \(callees)")
    }
}
#endif
