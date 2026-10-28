#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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
        let readIndex = try #require(callees.firstIndex(of: runtimeCallee(.arrayGet)), "got: \(callees)")
        return Array(callees[readIndex...])
    }

    @Test func testIndexedStringPlusAssignConvertsPrimitiveRHS() throws {
        let callees = try mainCallees("""
        fun main() { val a = arrayOf("x"); a[0] += 1 }
        """)
        let conversion = try #require(callees.firstIndex(of: runtimeCallee(.anyToString)))
        let concat = try #require(callees.firstIndex(of: "__kk_string_concat_flat"))
        #expect(conversion < concat)
        #expect(!callees.contains(runtimeCallee(.opAdd)))
    }

    @Test func testIndexedCompoundAssignCallsElementPlusOperator() throws {
        let callees = try mainCallees("""
        class V(val x: Int) { operator fun plus(o: V) = V(x + o.x) }
        fun main() {
            val a = arrayOf(V(1))
            a[0] += V(2)
        }
        """)
        let getIndex = try #require(callees.firstIndex(of: runtimeCallee(.arrayGet)), "got: \(callees)")
        let plusIndex = try #require(callees.firstIndex(of: "plus"), "Expected V.plus, got: \(callees)")
        let setIndex = try #require(callees.firstIndex(of: runtimeCallee(.arraySet)), "got: \(callees)")
        #expect(getIndex < plusIndex && plusIndex < setIndex, "got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.opAdd)), "The builtin add must not be applied to a class element, got: \(callees)")
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
        #expect(!callees.contains(runtimeCallee(.arraySet)), "An in-place plusAssign must not write the element back, got: \(callees)")
    }

    @Test func testIndexedPlusAssignSkipsTopLevelSetExtensionWriteBack() throws {
        let callees = try mainCallees("""
        class Acc { operator fun plusAssign(n: Int) {} }
        class AccBox { operator fun get(index: Int): Acc = Acc() }
        operator fun AccBox.set(index: Int, value: Acc) {}
        fun main() {
            val anchor = intArrayOf(1)
            val ignored = anchor[0]
            val box = AccBox()
            box[0] += 5
        }
        """)
        #expect(callees.contains("plusAssign"), "Expected Acc.plusAssign, got: \(callees)")
        #expect(!callees.contains("set"), "An in-place plusAssign must not call the top-level set extension, got: \(callees)")
    }

    @Test func testIndexedStringPlusAssignUsesStringConcatWithTopLevelMapSet() throws {
        let ctx = makeContextFromSource("""
        operator fun <K, V> MutableMap<K, V>.set(key: K, value: V) = put(key, value)
        fun main() {
            val commands: MutableMap<String, String> = HashMap()
            commands["c1"] += "932"
        }
        """)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("__kk_string_concat_flat"), "Expected nullable String concatenation, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.opAdd)), "String aggregates must not use integer addition, got: \(callees)")
    }

    @Test func testIndexedNonNullableStringPlusAssignUsesStringConcat() throws {
        let ctx = makeContextFromSource("""
        class Box { operator fun get(index: Int): String = "239" }
        operator fun Box.set(index: Int, value: String) {}
        fun main() {
            val box = Box()
            box[0] += "932"
        }
        """)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("__kk_string_concat_flat"), "Expected String concatenation, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.opAdd)), "String aggregates must not use integer addition, got: \(callees)")
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
        let setIndex = try #require(callees.firstIndex(of: runtimeCallee(.arraySet)), "got: \(callees)")
        #expect(incIndex < setIndex, "got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.opAdd)), "got: \(callees)")
    }

    @Test func testIndexedCompoundAssignReadsElementBeforeRightHandSide() throws {
        let callees = try mainCallees("""
        fun v(): Int = 1
        fun main() {
            val a = intArrayOf(10)
            a[0] += v()
        }
        """)
        let getIndex = try #require(callees.firstIndex(of: runtimeCallee(.arrayGet)), "got: \(callees)")
        let valueIndex = try #require(callees.firstIndex(of: "v"), "got: \(callees)")
        #expect(getIndex < valueIndex, "Kotlin evaluates get() before the right-hand side, got: \(callees)")
    }
}
#endif
