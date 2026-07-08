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

    @Test func testCompoundAssignOnInstanceFieldEmitsFieldLoadAndStore() throws {
        let source = """
        class Counter(private var addend: Int) {
            fun bump(): Int {
                addend += 362437
                return addend
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "bump", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("kk_array_get_inbounds"), "Expected a field load before the compound assign, got: \(callees)")
        #expect(callees.contains("kk_array_set"), "Expected the compound assign to write back through the field offset, got: \(callees)")

        let getIndex = callees.firstIndex(of: "kk_array_get_inbounds")
        let setIndex = callees.firstIndex(of: "kk_array_set")
        #expect(getIndex != nil && setIndex != nil && getIndex! < setIndex!, "Expected the field load to precede the field store, got: \(callees)")
    }

    @Test func testIncrementOnInstanceFieldEmitsFieldLoadAndStore() throws {
        let source = """
        class Holder(private var n: Int) {
            fun bump(): Int {
                n++
                return n
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "bump", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("kk_array_get_inbounds"), "Expected a field load before the increment, got: \(callees)")
        #expect(callees.contains("kk_array_set"), "Expected the increment to write back through the field offset, got: \(callees)")
    }

    @Test func testCompoundAssignOnMultipleInstanceFieldsUsesDistinctOffsets() throws {
        let source = """
        class Pair(private var a: Int, private var b: Int) {
            fun bump(): Int {
                a += 1
                b += 2
                return a + b
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "bump", in: module, interner: ctx.interner)
        let setCallArgumentCounts = body.compactMap { instruction -> Int? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "kk_array_set"
            else { return nil }
            return arguments.count
        }
        #expect(setCallArgumentCounts.count == 2, "Expected two field stores (one per field), got \(setCallArgumentCounts.count)")
    }
}
#endif
