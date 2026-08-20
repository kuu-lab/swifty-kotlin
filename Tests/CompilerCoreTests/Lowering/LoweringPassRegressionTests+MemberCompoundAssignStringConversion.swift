#if canImport(Testing)
@testable import CompilerCore
import Testing

// `receiver.field += x` where `field: String` and `x` is not itself a String
// must convert `x` the same way `+`/string-template concatenation does
// (Kotlin's `String.plus(other: Any?)` calls `x.toString()`) before handing
// both operands to kk_string_concat_flat, which assumes both arguments are
// already flat String aggregates. lowerMemberCompoundAssignExpr
// (CallLowerer+MemberAssignment.swift) used to skip this conversion entirely:
// a class instance silently vanished from the result and a primitive value
// crashed the process (kk_string_concat_flat reading an unboxed scalar as a
// String aggregate's pointer/length/hash fields). See
// Scripts/diff_cases/member_field_compound_assign_string_conversion.kt and
// BundledStdlibExecutionTests+MemberCompoundAssignStringConversion.swift for
// the compiled-and-run counterpart of this case.
extension LoweringPassRegressionTests {
    @Test
    func testMemberFieldCompoundAssignConvertsNonStringRHSBeforeConcat() throws {
        let source = """
        class Holder(var s: String)
        fun appendInt(h: Holder, x: Int) {
            h.s += x
        }
        fun main() {
            val h = Holder("n=")
            appendInt(h, 42)
            println(h.s)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "MemberCompoundAssignInt", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "appendInt", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_any_to_string"),
                    "a non-String RHS must be converted before kk_string_concat_flat; callees: \(callees)")
        }
    }

    @Test
    func testMemberFieldCompoundAssignCallsOverriddenToString() throws {
        let source = """
        class Foo(val x: Int) {
            override fun toString(): String = "Foo(" + x + ")"
        }
        class Holder(var s: String)
        fun appendFoo(h: Holder, f: Foo) {
            h.s += f
        }
        fun main() {
            val h = Holder("v=")
            appendFoo(h, Foo(1))
            println(h.s)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "MemberCompoundAssignClass", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "appendFoo", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("toString"),
                    "the RHS class value must call its own toString() override; callees: \(callees)")
        }
    }
}
#endif
