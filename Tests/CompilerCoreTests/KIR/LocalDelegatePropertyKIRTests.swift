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

    @Test func testLocalValProvideDelegateEmitsProvideDelegateThenGetValue() throws {
        // BUG-146: a local delegate whose factory exposes `provideDelegate` must
        // first call `provideDelegate` and then resolve getValue against its
        // *result* (the effective delegate), not bind the local to the raw
        // factory instance.
        let source = """
        class ValidatedDelegate(private val value: String) {
            operator fun getValue(thisRef: Any?, property: Any?): String = value
        }
        class DelegateFactory {
            operator fun provideDelegate(thisRef: Any?, prop: Any?): ValidatedDelegate = ValidatedDelegate("ok")
        }
        fun main() {
            val name by DelegateFactory()
            println(name)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "local provideDelegate declaration should compile without errors: \(diagnosticMessages)")

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(
                callees.contains("provideDelegate"),
                "Local delegated declaration with a provideDelegate operator should call provideDelegate, got: \(callees)"
            )
            #expect(
                callees.contains("getValue"),
                "Local provideDelegate declaration should still call getValue on the effective delegate, got: \(callees)"
            )
        }
    }

    @Test func testLocalValProvideDelegateGetValueReceivesProvideDelegateResult() throws {
        // The effective delegate is provideDelegate's return value, so getValue's
        // receiver argument must be provideDelegate's result — never the raw
        // factory instance (the pre-fix behavior bound `x` to the factory itself).
        let source = """
        class ValidatedDelegate(private val value: String) {
            operator fun getValue(thisRef: Any?, property: Any?): String = value
        }
        class DelegateFactory {
            operator fun provideDelegate(thisRef: Any?, prop: Any?): ValidatedDelegate = ValidatedDelegate("ok")
        }
        fun main() {
            val name by DelegateFactory()
            println(name)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            var provideDelegateResult: KIRExprID?
            var getValueArguments: [KIRExprID] = []
            for instruction in mainBody {
                guard case let .call(_, callee, arguments, result, _, _, _, _) = instruction else { continue }
                switch ctx.interner.resolve(callee) {
                case "provideDelegate":
                    provideDelegateResult = result
                case "getValue":
                    getValueArguments = arguments
                default:
                    break
                }
            }

            let resolvedProvideResult = try #require(provideDelegateResult, "expected a provideDelegate call in main")
            #expect(
                getValueArguments.first == resolvedProvideResult,
                "getValue's receiver must be provideDelegate's result (the effective delegate), not the raw factory instance"
            )
        }
    }

    @Test func testLocalVarProvideDelegateEmitsSetValueOnEffectiveDelegate() throws {
        let source = """
        class IntBox(private var stored: Int) {
            operator fun getValue(thisRef: Any?, property: Any?): Int = stored
            operator fun setValue(thisRef: Any?, property: Any?, value: Int) { stored = value }
        }
        class IntBoxFactory(private val initial: Int) {
            operator fun provideDelegate(thisRef: Any?, prop: Any?): IntBox = IntBox(initial)
        }
        fun main() {
            var counter by IntBoxFactory(10)
            counter = 42
            println(counter)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "local provideDelegate var should compile without errors: \(diagnosticMessages)")

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(
                callees.contains("provideDelegate"),
                "Expected a provideDelegate call, got: \(callees)"
            )
            #expect(
                callees.contains("setValue"),
                "Assigning a local provideDelegate var should call setValue, got: \(callees)"
            )
        }
    }

    /// BUG-052: a local `val x by lazy { ... }` kept the `kk_lazy_create` handle as
    /// the local's value, so reads observed the delegate object itself
    /// (`println(x)` printed `<object 0x...>`).
    @Test func testLocalLazyDelegateReadsCallLazyGetValue() throws {
        let source = """
        fun main() {
            val x by lazy { 42 }
            println(x)
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            // Through Lowering: StdlibDelegateLoweringPass turns the factory call
            // into kk_lazy_create.
            try runToLowering(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "local lazy delegate should compile without errors: \(diagnosticMessages)")

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_lazy_create"), "expected the lazy handle to be created, got: \(callees)")
            // One kk_lazy_get_value per read: reading through the runtime accessor
            // (instead of caching one value at the declaration) is what keeps the
            // initializer deferred until the first read.
            #expect(
                callees.filter { $0 == "kk_lazy_get_value" }.count == 2,
                "each read of a local lazy delegate must go through kk_lazy_get_value, got: \(callees)"
            )

            // println must consume kk_lazy_get_value's result, not the handle
            // returned by kk_lazy_create.
            // Values derived from kk_lazy_get_value's result, following the
            // boxing call the Int value goes through before println.
            var derivedValues: Set<KIRExprID> = []
            var lastCallArguments: [KIRExprID] = []
            for instruction in mainBody {
                guard case let .call(_, callee, arguments, result, _, _, _, _) = instruction else { continue }
                if ctx.interner.resolve(callee) == "kk_lazy_get_value", let result {
                    derivedValues.insert(result)
                } else if let result, arguments.contains(where: { derivedValues.contains($0) }) {
                    derivedValues.insert(result)
                }
                lastCallArguments = arguments
            }
            #expect(!derivedValues.isEmpty, "expected a kk_lazy_get_value call in main")
            #expect(
                lastCallArguments.contains(where: { derivedValues.contains($0) }),
                "println should print the lazily computed value, not the Lazy handle"
            )
        }
    }

    @Test func testStdlibLazyLocalDelegateInfersValueTypeFromFactory() throws {
        // The local's type must come from `Lazy<T>`'s argument, otherwise member
        // lookup on it (here `String.length`) fails.
        let source = """
        fun main() {
            val s by lazy { "hello" }
            println(s.length)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "`s` should be inferred as String: \(diagnosticMessages)")
        }
    }

    @Test func testStdlibObservableLocalDelegateReadsAndWritesThroughRuntime() throws {
        let source = """
        import kotlin.properties.Delegates
        fun main() {
            var y by Delegates.observable(1) { _, old, new -> println("$old -> $new") }
            y = 5
            println(y)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "local observable delegate should compile without errors: \(diagnosticMessages)")

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_observable_create"), "got: \(callees)")
            #expect(callees.contains("kk_observable_set_value"), "assignment must notify the delegate, got: \(callees)")
            #expect(callees.contains("kk_observable_get_value"), "read must query the delegate, got: \(callees)")
            #expect(
                !callees.contains("observable"),
                "the Delegates.observable factory stub must be replaced by its runtime entry point, got: \(callees)"
            )
        }
    }

    @Test func testStdlibNotNullLocalDelegateUsesRuntimeEntryPoints() throws {
        let source = """
        import kotlin.properties.Delegates
        fun main() {
            var w by Delegates.notNull<Int>()
            w = 3
            println(w)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "local notNull delegate should compile without errors: \(diagnosticMessages)")

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_notNull_create"), "got: \(callees)")
            #expect(callees.contains("kk_notNull_set_value"), "got: \(callees)")
            #expect(callees.contains("kk_notNull_get_value"), "got: \(callees)")
        }
    }

    @Test func testLocalLazyDelegateInitializerIsNotForcedAtDeclaration() throws {
        let source = """
        fun main() {
            val x by lazy { 42 }
            println("before")
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            // The `lazy` factory call is only rewritten to `kk_lazy_create` by
            // StdlibDelegateLoweringPass, which runs after this stage.
            let createIndex = try #require(callees.firstIndex(of: "lazy"))
            let getValueIndex = try #require(callees.firstIndex(of: "kk_lazy_get_value"))
            let printIndices = callees.indices.filter { callees[$0].hasPrefix("kk_println") }
            let firstPrintIndex = try #require(printIndices.first)

            #expect(createIndex < firstPrintIndex, "the delegate must be created at the declaration")
            #expect(
                getValueIndex > firstPrintIndex,
                "the value must only be read at the read site, not forced at the declaration: \(callees)"
            )
        }
    }

    @Test func testLocalLazyDelegateCapturedByLambdaReadsThroughGetValue() throws {
        // The lambda body is lowered under a fresh scope, so the delegate kind must
        // survive scope resets for the captured read to go through the accessor.
        let source = """
        fun main() {
            val x by lazy { 42 }
            val f = { x }
            println(f())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "capturing a local lazy delegate should compile: \(diagnosticMessages)")

            let module = try #require(ctx.kir)
            var sawGetValue = false
            module.arena.transformFunctions { function in
                for instruction in function.body {
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { continue }
                    if ctx.interner.resolve(callee) == "kk_lazy_get_value" { sawGetValue = true }
                }
                return function
            }
            #expect(sawGetValue, "a lambda reading a captured lazy local should call kk_lazy_get_value")
        }
    }
}
#endif
