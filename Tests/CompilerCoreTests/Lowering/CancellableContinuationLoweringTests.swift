@testable import CompilerCore
import Testing

@Suite
struct CancellableContinuationLoweringTests {
    @Test func intrinsicReceivesCurrentContinuationWhenBlockCapturesParameter() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
        suspend fun expose(block: (Continuation<Int>) -> Unit): Int =
            suspendCoroutineUninterceptedOrReturn { continuation ->
                block(continuation)
                7
            }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "CapturedContinuation", emit: .kirDump)
            try runToLowering(ctx)
            let module = try #require(ctx.kir)
            let wrapper = try findKIRFunction(named: "expose", in: module, interner: ctx.interner)
            let function = try LoweringTestRuntime.loweredSuspendFunction(for: wrapper, in: module, interner: ctx.interner)
            let calls = extractCallees(from: function.body, interner: ctx.interner)
            #expect(calls.contains(LoweringTestRuntime.name("function_invoke")))
            #expect(!calls.contains("<suspendCoroutineUninterceptedOrReturn>"))
            #expect(function.body.contains { instruction in
                guard case let .call(_, callee, _, _, canThrow, thrownResult, _, _) = instruction,
                      callee == LoweringTestRuntime.callee("function_invoke", interner: ctx.interner) else {
                    return false
                }
                return canThrow && thrownResult != nil
            })
            let failures = KIRVerifier.verify(module: module, symbols: ctx.sema?.symbols, interner: ctx.interner)
            #expect(failures.isEmpty)
        }
    }

    @Test func escapingLambdaPreservesIndirectThrowChannel() throws {
        let source = """
        fun wrapped(block: (Int) -> Int): (Int) -> Int = { value -> block(value) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ThrowingCallback", emit: .kirDump)
            try runToLowering(ctx)
            let module = try #require(ctx.kir)
            let adapterCalls = findAllKIRFunctions(in: module).filter {
                LoweringTestRuntime.operation(of: ctx.interner.resolve($0.name))?.hasPrefix("function_value_adapter_") == true
            }.flatMap(\.body).compactMap { instruction -> (Bool, KIRExprID?)? in
                guard case let .call(_, callee, _, _, canThrow, thrownResult, _, _) = instruction,
                      LoweringTestRuntime.operation(of: ctx.interner.resolve(callee))?.hasPrefix("lambda_") == true else {
                    return nil
                }
                return (canThrow, thrownResult)
            }
            #expect(!adapterCalls.isEmpty)
            #expect(adapterCalls.allSatisfy { $0.0 && $0.1 != nil })
            let failures = KIRVerifier.verify(module: module, symbols: ctx.sema?.symbols, interner: ctx.interner)
            #expect(failures.isEmpty)
        }
    }

    @Test func exceptionAliasExposesThrowableMembersInCatch() throws {
        let source = """
        typealias CallbackFailure = IllegalStateException
        fun failureMessage(): String? {
            try {
                throw IllegalStateException("cancelled")
            } catch (e: CallbackFailure) {
                return e.message
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ExceptionAlias", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)
            let module = try #require(ctx.kir)
            let failures = KIRVerifier.verify(module: module, symbols: ctx.sema?.symbols, interner: ctx.interner)
            #expect(failures.isEmpty)
        }
    }

    @Test func inlineSuspendBodyPreservesIntrinsicForLibraryConsumers() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

        suspend inline fun expose(crossinline block: (Continuation<Int>) -> Unit): Int =
            suspendCoroutineUninterceptedOrReturn { continuation ->
                block(continuation)
                7
            }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "InlineSuspend", emit: .kirDump)
            try runToLowering(ctx)
            let module = try #require(ctx.kir)
            let function = try findKIRFunction(named: "expose", in: module, interner: ctx.interner)
            let inlineBody = try #require(module.inlineBodiesBeforeCoroutineLowering[function.symbol])
            #expect(inlineBody.contains { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return callee == ctx.interner.intern("<suspendCoroutineUninterceptedOrReturn>")
            })
        }
    }
}
