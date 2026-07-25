#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-CAP-007 / BUG-014: local `by`-delegated declarations (`fun f() { val x by Prop() }`)
/// used to bind `x` straight to the delegate instance's own KIR value, never calling the
/// resolved `getValue`/`setValue` operator — see ExprLowerer+ControlFlowAndBlocks.swift's
/// `.localDecl`/`.localAssign` cases. Member and top-level delegated properties were
/// unaffected (they already route through a synthesized getter/setter accessor); only the
/// local-declaration path skipped the call entirely, regardless of the delegate's return type.
@Suite
struct LocalDelegatePropertyKIRTests {
    @Test func testLocalValCustomDelegateEmitsGetValueCall() throws {
        let source = """
        class IntProp {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        fun main() {
            val x by IntProp()
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "local custom delegate should compile without errors: \(diagnosticMessages)")

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(
                callees.contains("getValue"),
                "Local delegated declaration should call getValue, got: \(callees)"
            )
        }
    }

    @Test func testLocalValCustomDelegatePrintsGetValueResultNotDelegateInstance() throws {
        let source = """
        class IntProp {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        fun main() {
            val x by IntProp()
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            // println(Int) lowers to a runtime-specific callee (e.g. kk_println_any)
            // rather than literally "println", so identify it positionally instead:
            // main is `val x by IntProp(); println(x)`, so the getValue call must be
            // followed by exactly one more call — println — that consumes its result.
            var getValueResult: KIRExprID?
            var lastCallArguments: [KIRExprID] = []
            for instruction in mainBody {
                guard case let .call(_, callee, arguments, result, _, _, _, _) = instruction else { continue }
                if ctx.interner.resolve(callee) == "getValue" {
                    getValueResult = result
                }
                lastCallArguments = arguments
            }

            let resolvedGetValueResult = try #require(getValueResult, "expected a getValue call in main")
            #expect(
                lastCallArguments.contains(resolvedGetValueResult),
                "println should be called with getValue's result, not the Prop() instance itself"
            )
        }
    }

    @Test func testLocalVarCustomDelegateEmitsSetValueCallOnAssignment() throws {
        let source = """
        class IntProp {
            var backing: Int = 0
            operator fun getValue(thisRef: Any?, property: Any?): Int = backing
            operator fun setValue(thisRef: Any?, property: Any?, value: Int) {
                backing = value
            }
        }
        fun main() {
            var x by IntProp()
            x = 100
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "local custom delegate var should compile without errors: \(diagnosticMessages)")

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(
                callees.contains("setValue"),
                "Assigning a local delegated var should call setValue, got: \(callees)"
            )
            #expect(
                callees.filter { $0 == "getValue" }.count >= 2,
                "Expected a getValue call at declaration and a refresh getValue call after the assignment, got: \(callees)"
            )
        }
    }

    @Test func testLocalDelegateInfersPropertyTypeFromGetValueReturnType() throws {
        // Before the fix, a local delegate's inferred type fell back to the
        // delegate instance's own type (`IntProp`) instead of getValue's
        // return type, so arithmetic on the local failed overload resolution.
        let source = """
        class IntProp {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        fun main() {
            val x by IntProp()
            println(x + 1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            #expect(
                !(ctx.diagnostics.hasError),
                "x + 1 should type-check once x is correctly inferred as Int: \(diagnosticMessages)"
            )
        }
    }

    @Test func testStdlibLazyLocalDelegateIsUnaffected() throws {
        // Stdlib-special-cased delegate kinds (lazy/observable/vetoable/notNull)
        // are explicitly out of scope for this fix (KSP-491/492) and must keep
        // going through StdlibDelegateLoweringPass rather than the new
        // getValue-operator call path.
        let source = """
        fun main() {
            val x by lazy { 42 }
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "local lazy delegate should still compile without errors: \(diagnosticMessages)")
        }
    }
}
#endif
