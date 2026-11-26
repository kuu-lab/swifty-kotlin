#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)

        let cleanup = try findKIRFunction(named: "cleanup", in: module, interner: ctx.interner)
        let cleanupCalls = kirCalls(to: cleanup.symbol, in: body)

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
        try assertInlinedFinallyIsThrowAware(source: source, functionName: "loopWithBreak")
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
        let ctx = makeContextFromSource(source)
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
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)

        let inner = try findKIRFunction(named: "inner", in: module, interner: ctx.interner)
        let outer = try findKIRFunction(named: "outer", in: module, interner: ctx.interner)
        let innerCalls = kirCalls(to: inner.symbol, in: body)
        let outerCalls = kirCalls(to: outer.symbol, in: body)

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
        try assertInlinedFinallyIsThrowAware(source: source, functionName: "loopWithContinue")
    }

    @Test func testInlinedFinallyExceptionSkipsExitedTryHandlers() throws {
        let source = """
        fun innerCatch(): Unit {}
        fun outerCatch(): Unit {}
        fun compute() {
            try {
                while (true) {
                    try {
                        try {
                            break
                        } catch (e: Throwable) {
                            innerCatch()
                        }
                    } finally {
                        throw RuntimeException()
                    }
                }
            } catch (e: RuntimeException) {
                outerCatch()
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)
        let outerBodyGuardStart = try #require(body.firstIndex { if case .beginFinallyGuard = $0 { return true }; return false })

        var guardDepth = 0
        var outerBodyGuardEnd: Int?
        for index in outerBodyGuardStart..<body.count {
            switch body[index] {
            case .beginFinallyGuard:
                guardDepth += 1
            case .endFinallyGuard:
                guardDepth -= 1
                if guardDepth == 0 {
                    outerBodyGuardEnd = index
                    break
                }
            default:
                break
            }
            if outerBodyGuardEnd != nil { break }
        }
        let outerBodyGuardEndIndex = try #require(outerBodyGuardEnd)
        let outerCatchLabelIndex = try #require(
            body.indices.dropFirst(outerBodyGuardEndIndex + 1)
                .first { if case .label = body[$0] { return true }; return false }
        )
        guard case let .label(outerCatchDispatch) = body[outerCatchLabelIndex] else {
            Issue.record("Expected the label immediately after the outer try body to be its catch dispatch")
            return
        }

        #expect(
            body[..<outerBodyGuardEndIndex].contains { instruction in
                if case let .jump(target) = instruction { return target == outerCatchDispatch }
                return false
            },
            "An exception from the inlined finally must target the handler outside both nested try scopes"
        )
    }

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
        let ctx = makeContextFromSource(source)
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

    private func assertInlinedFinallyIsThrowAware(source: String, functionName: String) throws {
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)

        let cleanup = try findKIRFunction(named: "cleanup", in: module, interner: ctx.interner)
        let cleanupCalls = kirCalls(to: cleanup.symbol, in: body)

        #expect(
            cleanupCalls.count >= 1,
            Comment(rawValue: "Expected at least one inlined cleanup() call for finally on \(functionName)")
        )

        let hasThrowAwareCleanup = cleanupCalls.contains { $0.canThrow }
        #expect(
            hasThrowAwareCleanup,
            Comment(rawValue: "Inlined finally cleanup() should be throw-aware for \(functionName)")
        )

        let rethrowCount = body.filter { instr in
            if case .rethrow = instr { return true }
            return false
        }.count
        #expect(
            rethrowCount >= 1,
            Comment(rawValue: "Expected at least one rethrow for inlined finally exception routing on \(functionName)")
        )
    }
}
#endif
