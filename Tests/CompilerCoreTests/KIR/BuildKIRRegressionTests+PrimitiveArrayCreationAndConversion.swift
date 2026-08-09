#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// STDLIB-004: Codegen coverage for primitive array factory calls and
// lambda constructors.  These tests verify the KIR lowering output so
// that any regression in the array-creation code path is caught early.
extension BuildKIRRegressionTests {

    /// Primitive array factories, lambda constructors, and conversions must
    /// lower to the expected runtime helpers in a single compilation.
    @Test func testPrimitiveArrayCreationAndConversionKIR() throws {
        let sources: [String] = [
            // 0: intArrayOf factory
            """
            fun make0() = intArrayOf(1, 2, 3)
            fun main0(): Int {
                val arr = make0()
                return arr.size
            }
            """,
            // 1: byteArrayOf factory
            """
            fun make1() = byteArrayOf(1.toByte(), 127.toByte())
            fun main1(): Int {
                val arr = make1()
                return arr.size
            }
            """,
            // 2: charArrayOf factory
            """
            fun make2() = charArrayOf('a', 'b', 'c')
            fun main2(): Int {
                val arr = make2()
                return arr.size
            }
            """,
            // 3: IntArray lambda constructor
            """
            fun make3() = IntArray(3) { it * 2 }
            fun main3(): Int {
                val arr = make3()
                return arr.size
            }
            """,
            // 4: ByteArray lambda constructor
            """
            fun make4() = ByteArray(4) { (it + 1).toByte() }
            fun main4(): Int {
                val arr = make4()
                return arr.size
            }
            """,
            // 5: ByteArray size-only constructor
            """
            fun make5() = ByteArray(8)
            fun main5(): Int {
                val arr = make5()
                return arr.size
            }
            """,
            // 6: IntArray size-only constructor
            """
            fun make6() = IntArray(3)
            fun main6(): Int {
                val arr = make6()
                return arr.size
            }
            """,
            // 7: List.toIntArray conversion
            """
            fun convert7(list: List<Int>) = list.toIntArray()
            fun main7(): Int {
                val arr = convert7(listOf(10, 20, 30))
                return arr.size
            }
            """,
            // 8: IntArray.toList conversion
            """
            fun convert8(arr: IntArray) = arr.toList()
            fun main8(): Int {
                val list = convert8(intArrayOf(1, 2))
                return list.size
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            // 0: intArrayOf must lower to kk_array_of
            do {
                let body = try findKIRFunctionBody(named: "make0", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_of"), "intArrayOf must lower to kk_array_of; got: \(callNames)")
                #expect(!callNames.contains("intArrayOf"), "intArrayOf call should have been rewritten; got: \(callNames)")
            }

            // 1: byteArrayOf must lower to kk_array_of
            do {
                let body = try findKIRFunctionBody(named: "make1", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_of"), "byteArrayOf must lower to kk_array_of; got: \(callNames)")
            }

            // 2: charArrayOf must lower to kk_array_of
            do {
                let body = try findKIRFunctionBody(named: "make2", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_of"), "charArrayOf must lower to kk_array_of; got: \(callNames)")
            }

            // 3: IntArray(n) { init } must lower to kk_array_new_checked and kk_array_set
            do {
                let body = try findKIRFunctionBody(named: "make3", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_new_checked"), "IntArray(n) { init } must emit kk_array_new_checked; got: \(callNames)")
                #expect(callNames.contains("kk_array_set"), "IntArray(n) { init } must emit kk_array_set; got: \(callNames)")

                let throwFlags = extractThrowFlags(from: body, interner: interner)
                #expect(throwFlags["kk_array_new_checked"]?.allSatisfy { $0 == true } == true, "kk_array_new_checked inside constructor must be throwing")
            }

            // 4: ByteArray(n) { init } must lower to kk_array_new_checked and kk_array_set
            do {
                let body = try findKIRFunctionBody(named: "make4", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_new_checked"), "ByteArray(n) { init } must emit kk_array_new_checked; got: \(callNames)")
                #expect(callNames.contains("kk_array_set"), "ByteArray(n) { init } must emit kk_array_set; got: \(callNames)")
            }

            // 5: ByteArray(n) (size-only) must lower to kk_array_new_checked without fill loop
            do {
                let body = try findKIRFunctionBody(named: "make5", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_new_checked"), "ByteArray(n) (size-only) must emit kk_array_new_checked; got: \(callNames)")
                #expect(!callNames.contains("kk_array_set"), "ByteArray(n) (size-only) must not emit a fill loop; got: \(callNames)")
                #expect(!callNames.contains("ByteArray"), "ByteArray(n) (size-only) must not fall through to an unresolved 'ByteArray' call; got: \(callNames)")
            }

            // 6: IntArray(n) (size-only) must lower to kk_array_new_checked without fill loop
            do {
                let body = try findKIRFunctionBody(named: "make6", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_new_checked"), "IntArray(n) (size-only) must emit kk_array_new_checked; got: \(callNames)")
                #expect(!callNames.contains("kk_array_set"), "IntArray(n) (size-only) must not emit a fill loop; got: \(callNames)")
                #expect(!callNames.contains("IntArray"), "IntArray(n) (size-only) must not fall through to an unresolved 'IntArray' call; got: \(callNames)")
            }

            // 7: List<Int>.toIntArray() must lower to the bundled source-backed declaration
            do {
                let body = try findKIRFunctionBody(named: "convert7", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(!callNames.contains("kk_list_toIntArray"), "List<Int>.toIntArray() must no longer use the removed kk_list_toIntArray bridge; got: \(callNames)")
                #expect(callNames == ["toIntArray"], "List<Int>.toIntArray() must lower to a single call of the bundled declaration; got: \(callNames)")

                let calleeSymbol = try #require(body.compactMap { instruction -> SymbolID? in
                    guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                          interner.resolve(callee) == "toIntArray"
                    else { return nil }
                    return symbol
                }.first)
                #expect(ctx.sema?.symbols.externalLinkName(for: calleeSymbol) == nil)
            }

            // 8: IntArray.toList() must lower to a runtime toList call
            do {
                let body = try findKIRFunctionBody(named: "convert8", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                let resolved = callNames.contains("kk_intArray_toList") || callNames.contains("kk_array_toList")
                #expect(resolved, "IntArray.toList() must lower to a runtime toList call; got: \(callNames)")
                #expect(!callNames.contains("toList"), "toList must be fully rewritten to a runtime call; got: \(callNames)")
            }
        }
    }
}
#endif
