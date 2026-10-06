#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-652: `ClosedRange.endInclusive` reads on concrete ranges used to fall through the range
/// property lowering (only the legacy `end` alias was mapped), so KIR emitted a call to a bare
/// `endInclusive` symbol and linking failed with `undefined reference to 'endInclusive'`.
@Suite
struct RangeEndInclusiveLoweringTests {
    @Test(arguments: ["Double", "Float"])
    func testFloatingPointRangeParameterUsesRuntimeProbeAndInterfaceGetter(element: String) throws {
        let ctx = makeContextFromSource("""
        fun bounds(range: ClosedFloatingPointRange<\(element)>): \(element) = range.endInclusive - range.start
        """)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "bounds", in: module, interner: ctx.interner)
        let names = extractCallees(from: body, interner: ctx.interner)
        #expect(names.filter { $0 == "__kk_floating_range_endpoint_or_null" }.count == 2)
        #expect(names.filter { $0 == "kk_unbox_\(element.lowercased())" }.count == 2)
        let getterDispatches = body.compactMap { instruction -> KIRDispatchKind? in
            guard case let .virtualCall(_, _, _, _, _, _, _, dispatch) = instruction else { return nil }
            return dispatch
        }
        #expect(getterDispatches.count == 2)
        #expect(getterDispatches.allSatisfy {
            if case .itableDynamic = $0 { return true }
            return false
        })
        #expect(!names.contains("endInclusive"))
    }

    private func callNames(in source: String, function: String) throws -> [String] {
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: function, in: module, interner: ctx.interner)
        return extractCallees(from: body, interner: ctx.interner)
    }

    @Test func testIntRangeEndInclusiveLowersToRuntimeGetter() throws {
        let names = try callNames(
            in: """
            fun bounds(): Int {
                val range = 1..5
                return range.endInclusive - range.start
            }
            """,
            function: "bounds"
        )
        #expect(names.contains("__kk_range_last"), "Expected __kk_range_last for IntRange.endInclusive, got: \(names)")
        #expect(names.contains("__kk_range_first"), "Expected __kk_range_first for IntRange.start, got: \(names)")
        #expect(!names.contains("endInclusive"), "endInclusive must not be emitted as a bare callee, got: \(names)")
    }

    @Test func testLongRangeEndInclusiveLowersToTypedRuntimeGetter() throws {
        let names = try callNames(
            in: """
            fun bounds(): Long {
                val range = 1L..5L
                return range.endInclusive - range.start
            }
            """,
            function: "bounds"
        )
        #expect(names.contains("__kk_range_last"), "Expected __kk_range_last for LongRange.endInclusive, got: \(names)")
        #expect(!names.contains("endInclusive"), "endInclusive must not be emitted as a bare callee, got: \(names)")
    }

    @Test func testFloatingPointRangeBoundsUseTypedRuntimeGetters() throws {
        for (type, suffix, prefix) in [("Double", "", "double"), ("Float", "f", "float")] {
            let names = try callNames(
                in: """
                fun bounds(): \(type) {
                    val range = -1.25\(suffix)..2.5\(suffix)
                    val start: \(type) = range.start
                    val end: \(type) = range.endInclusive
                    return end - start
                }
                """,
                function: "bounds"
            )
            #expect(names.contains("__kk_\(prefix)_range_start"))
            #expect(names.contains("__kk_\(prefix)_range_endInclusive"))
            #expect(!names.contains("__kk_range_first"))
            #expect(!names.contains("__kk_range_last"))
        }
    }
}
#endif
