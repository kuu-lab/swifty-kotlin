#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-652: `ClosedRange.endInclusive` reads on concrete ranges used to fall through the range
/// property lowering (only the legacy `end` alias was mapped), so KIR emitted a call to a bare
/// `endInclusive` symbol and linking failed with `undefined reference to 'endInclusive'`.
@Suite
struct RangeEndInclusiveLoweringTests {
    private func callNames(in source: String, function: String) throws -> [String] {
        var names: [String] = []
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: function, in: module, interner: ctx.interner)
            names = body.compactMap { instruction -> String? in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
                return ctx.interner.resolve(callee)
            }
        }
        return names
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
        #expect(names.contains("kk_range_last"), "Expected kk_range_last for IntRange.endInclusive, got: \(names)")
        #expect(names.contains("kk_range_first"), "Expected kk_range_first for IntRange.start, got: \(names)")
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
        #expect(names.contains("kk_long_range_last"), "Expected kk_long_range_last for LongRange.endInclusive, got: \(names)")
        #expect(!names.contains("endInclusive"), "endInclusive must not be emitted as a bare callee, got: \(names)")
    }
}
#endif
