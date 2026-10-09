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
        let calls = kirCalls(in: body)
        #expect(kirCalls(to: .floatingRangeEndpoint, in: body, interner: ctx.interner).count == 2)
        let unbox: KIRRuntimeFunction = element == "Double" ? .unboxDouble : .unboxFloat
        #expect(kirCalls(to: unbox, in: body, interner: ctx.interner).count == 2)
        let getterDispatches = body.compactMap { instruction -> KIRDispatchKind? in
            guard case let .virtualCall(_, _, _, _, _, _, _, dispatch) = instruction else { return nil }
            return dispatch
        }
        #expect(getterDispatches.count == 2)
        #expect(getterDispatches.allSatisfy {
            if case .itableDynamic = $0 { return true }
            return false
        })
        #expect(!calls.contains { $0.callee == ctx.interner.intern("endInclusive") })
    }

    private func loweredCalls(in source: String, function: String) throws -> (StringInterner, [KIRCallSite]) {
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: function, in: module, interner: ctx.interner)
        return (ctx.interner, kirCalls(in: body))
    }

    @Test func testIntRangeEndInclusiveLowersToRuntimeGetter() throws {
        let (interner, calls) = try loweredCalls(
            in: """
            fun bounds(): Int {
                val range = 1..5
                return range.endInclusive - range.start
            }
            """,
            function: "bounds"
        )
        #expect(calls.contains { $0.callee == KIRRuntimeFunction.rangeLast.name(in: interner) }, "Expected __kk_range_last for IntRange.endInclusive, got: \(calls)")
        #expect(calls.contains { $0.callee == KIRRuntimeFunction.rangeFirst.name(in: interner) }, "Expected __kk_range_first for IntRange.start, got: \(calls)")
        #expect(!calls.contains { $0.callee == interner.intern("endInclusive") }, "endInclusive must not be emitted as a bare callee, got: \(calls)")
    }

    @Test func testLongRangeEndInclusiveLowersToTypedRuntimeGetter() throws {
        let (interner, calls) = try loweredCalls(
            in: """
            fun bounds(): Long {
                val range = 1L..5L
                return range.endInclusive - range.start
            }
            """,
            function: "bounds"
        )
        #expect(calls.contains { $0.callee == KIRRuntimeFunction.rangeLast.name(in: interner) }, "Expected __kk_range_last for LongRange.endInclusive, got: \(calls)")
        #expect(!calls.contains { $0.callee == interner.intern("endInclusive") }, "endInclusive must not be emitted as a bare callee, got: \(calls)")
    }

    @Test func testFloatingPointRangeBoundsUseTypedRuntimeGetters() throws {
        let cases: [(String, String, KIRRuntimeFunction, KIRRuntimeFunction)] = [
            ("Double", "", .doubleRangeStart, .doubleRangeEndInclusive),
            ("Float", "f", .floatRangeStart, .floatRangeEndInclusive),
        ]
        for (type, suffix, start, end) in cases {
            let (interner, calls) = try loweredCalls(
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
            #expect(calls.contains { $0.callee == start.name(in: interner) })
            #expect(calls.contains { $0.callee == end.name(in: interner) })
            #expect(!calls.contains { $0.callee == KIRRuntimeFunction.rangeFirst.name(in: interner) })
            #expect(!calls.contains { $0.callee == KIRRuntimeFunction.rangeLast.name(in: interner) })
        }
    }
}
#endif
