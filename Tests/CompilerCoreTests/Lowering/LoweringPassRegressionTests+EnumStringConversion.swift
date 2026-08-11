#if canImport(Testing)
@testable import CompilerCore
import Testing

// An enum value that stays statically typed as its enum class is represented by
// its bare ordinal. BUG-179 taught the Any-erasure boundary to box that ordinal
// together with its entry name, but a value that never crosses that boundary
// reached string conversion as a plain integer and rendered as the number:
// `"$d"` printed `2` and `d.toString()` printed `2` rather than `SOUTH`.
//
// Both now route through the enum class's `$enumOrdinalToName$<id>` helper --
// interpolation/concatenation at KIR lowering time (emitAnyToStringWithNullGuard,
// the single funnel every stringification of an Any-erased value goes through)
// and `toString()` in EnumNameAccessLoweringPass, which is where the
// `kotlin.Any.toString` binding an enum receiver falls back to is rewritten.
extension LoweringPassRegressionTests {
    @Test
    func testEnumInterpolationLowersToOrdinalToNameHelper() throws {
        let source = """
        enum class Direction { NORTH, EAST, SOUTH, WEST }
        fun render(d: Direction): String {
            return "dir=$d"
        }
        fun main() {
            println(render(Direction.SOUTH))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumInterpolation", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains(where: { $0.hasPrefix("$enumOrdinalToName$") }),
                    "the interpolated enum must be converted via the name helper; callees: \(callees)")
            #expect(!callees.contains("kk_any_to_string"),
                    "the ordinal must not reach the generic Any conversion; callees: \(callees)")
        }
    }

    @Test
    func testEnumToStringLowersToOrdinalToNameHelper() throws {
        let source = """
        enum class Direction { NORTH, EAST, SOUTH, WEST }
        fun render(d: Direction): String {
            return d.toString()
        }
        fun main() {
            println(render(Direction.WEST))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumToString", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains(where: { $0.hasPrefix("$enumOrdinalToName$") }),
                    "toString() on an enum receiver must use the name helper; callees: \(callees)")
            #expect(!callees.contains("kk_any_member_to_string"),
                    "the kotlin.Any binding must be rewritten away; callees: \(callees)")
        }
    }

    // A non-enum receiver must keep using the generic conversion: the rewrite is
    // keyed on the receiver's static type, not on the callee alone.
    @Test
    func testNonEnumToStringKeepsGenericAnyConversion() throws {
        let source = """
        class Holder(val code: Int)
        fun render(h: Holder): String {
            return h.toString()
        }
        fun main() {
            println(render(Holder(1)))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "NonEnumToString", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(!callees.contains(where: { $0.hasPrefix("$enumOrdinalToName$") }),
                    "a class receiver has no ordinal to name; callees: \(callees)")
        }
    }
}
#endif
