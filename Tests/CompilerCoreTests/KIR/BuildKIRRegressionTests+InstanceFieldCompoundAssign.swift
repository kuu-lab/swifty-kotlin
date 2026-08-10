#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    // Regression coverage for a bug where `field += x` / `field++` on a
    // `private var` instance property (accessed via implicit `this`) silently
    // dropped the write: it only updated the KIR lowering context's
    // local-value cache (meant for real locals/params) instead of storing
    // back through the object's field offset, so the mutation never persisted.
    // Plain reassignment (`field = field + x`) already went through the
    // correct `kk_array_set` write-back path, which is why rewriting the
    // compound assign as an explicit reassignment was a working workaround.

    @Test func testInstanceFieldCompoundAssignAndIncrement() throws {
        let sources = [
            """
            class Counter0(private var addend: Int) {
                fun bump0(): Int {
                    addend += 362437
                    return addend
                }
            }
            """,
            """
            class Holder1(private var n: Int) {
                fun bump1(): Int {
                    n++
                    return n
                }
            }
            """,
            """
            class Pair2(private var a: Int, private var b: Int) {
                fun bump2(): Int {
                    a += 1
                    b += 2
                    return a + b
                }
            }
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let interner = ctx.interner

        // Counter0: compound assign must load and store the field.
        do {
            let body = try findKIRFunctionBody(named: "bump0", in: module, interner: interner)
            let callees = extractCallees(from: body, interner: interner)

            #expect(callees.contains("kk_array_get_inbounds"), "Expected a field load before the compound assign, got: \(callees)")
            #expect(callees.contains("kk_array_set"), "Expected the compound assign to write back through the field offset, got: \(callees)")

            let getIndex = callees.firstIndex(of: "kk_array_get_inbounds")
            let setIndex = callees.firstIndex(of: "kk_array_set")
            #expect(getIndex != nil && setIndex != nil && getIndex! < setIndex!, "Expected the field load to precede the field store, got: \(callees)")
        }

        // Holder1: increment must load and store the field.
        do {
            let body = try findKIRFunctionBody(named: "bump1", in: module, interner: interner)
            let callees = extractCallees(from: body, interner: interner)

            #expect(callees.contains("kk_array_get_inbounds"), "Expected a field load before the increment, got: \(callees)")
            #expect(callees.contains("kk_array_set"), "Expected the increment to write back through the field offset, got: \(callees)")
        }

        // Pair2: two field stores must target distinct offsets.
        do {
            let body = try findKIRFunctionBody(named: "bump2", in: module, interner: interner)

            var intLiteralByResult: [KIRExprID: Int64] = [:]
            for instruction in body {
                if case let .constValue(result, .intLiteral(value)) = instruction {
                    intLiteralByResult[result] = value
                }
            }
            let storeOffsets = body.compactMap { instruction -> Int64? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      interner.resolve(callee) == "kk_array_set",
                      arguments.count == 3
                else { return nil }
                return intLiteralByResult[arguments[1]]
            }

            #expect(storeOffsets.count == 2, "Expected two field stores (one per field), got \(storeOffsets.count)")
            #expect(Set(storeOffsets).count == 2, "Expected the two field stores to target distinct offsets, got \(storeOffsets)")
        }
    }
}
#endif
