#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct FinallyExceptionRouteTests {

    @Test func testReturnInTryCatchFinallyRoutesExceptionOutward() throws {
        let source = """
        fun cleanup(): Unit {}
        fun compute(): Int {
            try {
                return 42
            } catch (e: Exception) {
                return -1
            } finally {
                cleanup()
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)

            let cleanupCalls = body.enumerated().compactMap { (index, instr) -> (index: Int, canThrow: Bool, hasThrownResult: Bool)? in
                guard case let .call(_, callee, _, _, canThrow, thrownResult, _, _) = instr,
                      ctx.interner.resolve(callee) == "cleanup"
                else { return nil }
                return (index: index, canThrow: canThrow, hasThrownResult: thrownResult != nil)
            }

            #expect(
                cleanupCalls.count >= 1,
                "Expected at least one inlined cleanup() call"
            )

            let rethrowIndices = body.indices.filter { index in
                if case .rethrow = body[index] { return true }
                return false
            }

            let returnValueIndices = body.indices.filter { index in
                if case .returnValue = body[index] { return true }
                return false
            }

            let inlinedCleanupCalls = cleanupCalls.filter { call in
                returnValueIndices.contains { retIdx in call.index < retIdx }
            }

            let hasThrowAwareInlinedCleanup = inlinedCleanupCalls.contains { $0.canThrow }
            #expect(
                hasThrowAwareInlinedCleanup,
                "Inlined finally cleanup() should be wrapped with throw-aware handling (canThrow: true)"
            )

            #expect(
                rethrowIndices.count >= 1,
                "Expected at least one rethrow instruction for inlined finally exception routing"
            )
        }
    }

    @Test func testBreakInTryCatchFinallyRoutesExceptionOutward() throws {
        let source = """
        fun cleanup(): Unit {}
        fun loopWithBreak(): Unit {
            while (true) {
                try {
                    break
                } catch (e: Exception) {
                } finally {
                    cleanup()
                }
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "loopWithBreak", in: module, interner: ctx.interner)

            let cleanupCalls = body.enumerated().compactMap { (index, instr) -> (index: Int, canThrow: Bool)? in
                guard case let .call(_, callee, _, _, canThrow, _, _, _) = instr,
                      ctx.interner.resolve(callee) == "cleanup"
                else { return nil }
                return (index: index, canThrow: canThrow)
            }

            #expect(
                cleanupCalls.count >= 1,
                "Expected at least one inlined cleanup() call for finally on break"
            )

            let rethrowIndices = body.indices.filter { index in
                if case .rethrow = body[index] { return true }
                return false
            }

            let hasThrowAwareCleanup = cleanupCalls.contains { $0.canThrow }
            #expect(
                hasThrowAwareCleanup,
                "Inlined finally cleanup() should be throw-aware for break path"
            )

            #expect(
                rethrowIndices.count >= 1,
                "Expected at least one rethrow for inlined finally exception routing on break"
            )
        }
    }

    @Test func testInlinedFinallyWithNoCallsSkipsExceptionWrapping() throws {
        let source = """
        var x: Int = 0
        fun compute(): Int {
            try {
                return 42
            } finally {
                x = 1
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)

            let returnValueIndices = body.indices.filter { index in
                if case .returnValue = body[index] { return true }
                return false
            }

            let hasReturnValue = !returnValueIndices.isEmpty
            #expect(hasReturnValue, "Expected at least one returnValue instruction")

            #expect(!body.isEmpty, "Expected non-empty function body")
        }
    }

    @Test func testNestedTryFinallyExceptionRouting() throws {
        let source = """
        fun outer(): Unit {}
        fun inner(): Unit {}
        fun compute(): Int {
            try {
                try {
                    return 42
                } finally {
                    inner()
                }
            } finally {
                outer()
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)

            let innerCalls = body.filter { instr in
                guard case let .call(_, callee, _, _, _, _, _, _) = instr else { return false }
                return ctx.interner.resolve(callee) == "inner"
            }
            let outerCalls = body.filter { instr in
                guard case let .call(_, callee, _, _, _, _, _, _) = instr else { return false }
                return ctx.interner.resolve(callee) == "outer"
            }

            #expect(
                innerCalls.count >= 1,
                "Expected at least one inner() call"
            )
            #expect(
                outerCalls.count >= 1,
                "Expected at least one outer() call"
            )

            let rethrowCount = body.filter { instr in
                if case .rethrow = instr { return true }
                return false
            }.count

            #expect(
                rethrowCount >= 1,
                "Expected rethrow instructions for nested finally exception routing"
            )
        }
    }

    @Test func testContinueInTryCatchFinallyRoutesExceptionOutward() throws {
        let source = """
        fun cleanup(): Unit {}
        fun counter(): Boolean = false
        fun loopWithContinue(): Unit {
            while (counter()) {
                try {
                    continue
                } catch (e: Exception) {
                } finally {
                    cleanup()
                }
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "loopWithContinue", in: module, interner: ctx.interner)

            let cleanupCalls = body.enumerated().compactMap { (index, instr) -> (index: Int, canThrow: Bool)? in
                guard case let .call(_, callee, _, _, canThrow, _, _, _) = instr,
                      ctx.interner.resolve(callee) == "cleanup"
                else { return nil }
                return (index: index, canThrow: canThrow)
            }

            #expect(
                cleanupCalls.count >= 1,
                "Expected at least one inlined cleanup() call for finally on continue"
            )

            let hasThrowAwareCleanup = cleanupCalls.contains { $0.canThrow }
            #expect(
                hasThrowAwareCleanup,
                "Inlined finally cleanup() should be throw-aware for continue path"
            )

            let rethrowCount = body.filter { instr in
                if case .rethrow = instr { return true }
                return false
            }.count

            #expect(
                rethrowCount >= 1,
                "Expected at least one rethrow for inlined finally exception routing on continue"
            )
        }
    }

    // MARK: - usePinned nested inside an outer try (CODE-001 guard placement)

    /// Verifies that `usePinned`'s block-call is wrapped in its own nested
    /// beginFinallyGuard/endFinallyGuard region when `usePinned` is itself
    /// nested inside an outer try. Without this guard, the outer try's own
    /// appendThrowAwareInstructions pass would re-wrap the already-routed
    /// block call, inserting a premature jump to the outer catch dispatch
    /// that races ahead of usePinned's own unpin() cleanup — the same class
    /// of bug fixed for the try/catch/finally and `use{}` cases, but not
    /// observable via printed output since unpin() has no visible side
    /// effect. This checks the KIR shape directly instead: two levels of
    /// beginFinallyGuard nesting must be reachable (the outer try's own body
    /// guard, plus usePinned's own guard around its block call).
    @Test func testUsePinnedNestedInOuterTryGuardsBlockCallFromOuterRewrap() throws {
        let source = """
        import kotlinx.cinterop.ExperimentalForeignApi
        import kotlinx.cinterop.Pinned
        import kotlinx.cinterop.usePinned

        class Box(var value: Int)

        @ExperimentalForeignApi
        fun main() {
            try {
                val box = Box(42)
                box.usePinned { pinned: Pinned<Box> ->
                    pinned.get().value
                }
            } catch (e: Exception) {
                println("caught")
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            var depth = 0
            var maxDepth = 0
            var sawCallAtNestedDepth = false
            for instr in body {
                switch instr {
                case .beginFinallyGuard:
                    depth += 1
                    maxDepth = max(maxDepth, depth)
                case .endFinallyGuard:
                    depth -= 1
                case .call where depth >= 2:
                    sawCallAtNestedDepth = true
                default:
                    break
                }
            }

            #expect(depth == 0, "beginFinallyGuard/endFinallyGuard must be balanced")
            #expect(
                maxDepth >= 2,
                "Expected usePinned's block-call guard nested inside the outer try's own body guard"
            )
            #expect(
                sawCallAtNestedDepth,
                "Expected the usePinned block-call itself inside the doubly-guarded region"
            )
        }
    }
}
#endif
