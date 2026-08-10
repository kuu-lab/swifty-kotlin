#if canImport(Testing)
@testable import CompilerCore
import Testing

/// CODE-001: Tests ensuring that exceptions thrown inside inlined finally
/// blocks are routed *outward* (via rethrow) rather than being caught by
/// the enclosing try-catch that owns the finally block.
///
/// In Kotlin, when a finally block throws, the new exception replaces the
/// original and propagates to the next outer exception handler, NOT to the
/// catch clauses of the try statement the finally belongs to.
@Suite
struct FinallyExceptionRouteTests {

    @Test func testFinallyExceptionRouting() throws {
        let sources = [
            """
            package sample0

            fun cleanup0(): Unit {}
            fun compute0(): Int {
                try {
                    return 42
                } catch (e: Exception) {
                    return -1
                } finally {
                    cleanup0()
                }
            }
            """,
            """
            package sample1

            fun cleanup1(): Unit {}
            fun loopWithBreak1(): Unit {
                while (true) {
                    try {
                        break
                    } catch (e: Exception) {
                    } finally {
                        cleanup1()
                    }
                }
            }
            """,
            """
            package sample2

            var x2: Int = 0
            fun compute2(): Int {
                try {
                    return 42
                } finally {
                    x2 = 1
                }
            }
            """,
            """
            package sample3

            fun outer3(): Unit {}
            fun inner3(): Unit {}
            fun compute3(): Int {
                try {
                    try {
                        return 42
                    } finally {
                        inner3()
                    }
                } finally {
                    outer3()
                }
            }
            """,
            """
            package sample4

            fun cleanup4(): Unit {}
            fun counter4(): Boolean = false
            fun loopWithContinue4(): Unit {
                while (counter4()) {
                    try {
                        continue
                    } catch (e: Exception) {
                    } finally {
                        cleanup4()
                    }
                }
            }
            """,
            """
            package sample5

            import kotlinx.cinterop.ExperimentalForeignApi
            import kotlinx.cinterop.Pinned
            import kotlinx.cinterop.usePinned

            class Box5(var value: Int)

            @ExperimentalForeignApi
            fun main5() {
                try {
                    val box = Box5(42)
                    box.usePinned { pinned: Pinned<Box5> ->
                        pinned.get().value
                    }
                } catch (e: Exception) {
                    println("caught")
                }
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let body = try findKIRFunctionBody(named: "compute0", in: module, interner: interner)

                let cleanupCalls = body.enumerated().compactMap { (index, instr) -> (index: Int, canThrow: Bool, hasThrownResult: Bool)? in
                    guard case let .call(_, callee, _, _, canThrow, thrownResult, _, _) = instr,
                          interner.resolve(callee) == "cleanup0"
                    else { return nil }
                    return (index: index, canThrow: canThrow, hasThrownResult: thrownResult != nil)
                }

                #expect(
                    cleanupCalls.count >= 1,
                    "Expected at least one inlined cleanup0() call"
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
                    "Inlined finally cleanup0() should be wrapped with throw-aware handling (canThrow: true)"
                )

                #expect(
                    rethrowIndices.count >= 1,
                    "Expected at least one rethrow instruction for inlined finally exception routing"
                )
            }

            do {
                let body = try findKIRFunctionBody(named: "loopWithBreak1", in: module, interner: interner)

                let cleanupCalls = body.enumerated().compactMap { (index, instr) -> (index: Int, canThrow: Bool)? in
                    guard case let .call(_, callee, _, _, canThrow, _, _, _) = instr,
                          interner.resolve(callee) == "cleanup1"
                    else { return nil }
                    return (index: index, canThrow: canThrow)
                }

                #expect(
                    cleanupCalls.count >= 1,
                    "Expected at least one inlined cleanup1() call for finally on break"
                )

                let rethrowIndices = body.indices.filter { index in
                    if case .rethrow = body[index] { return true }
                    return false
                }

                let hasThrowAwareCleanup = cleanupCalls.contains { $0.canThrow }
                #expect(
                    hasThrowAwareCleanup,
                    "Inlined finally cleanup1() should be throw-aware for break path"
                )

                #expect(
                    rethrowIndices.count >= 1,
                    "Expected at least one rethrow for inlined finally exception routing on break"
                )
            }

            do {
                let body = try findKIRFunctionBody(named: "compute2", in: module, interner: interner)

                let returnValueIndices = body.indices.filter { index in
                    if case .returnValue = body[index] { return true }
                    return false
                }

                let hasReturnValue = !returnValueIndices.isEmpty
                #expect(hasReturnValue, "Expected at least one returnValue instruction")

                #expect(!body.isEmpty, "Expected non-empty function body")
            }

            do {
                let body = try findKIRFunctionBody(named: "compute3", in: module, interner: interner)

                let innerCalls = body.filter { instr in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instr else { return false }
                    return interner.resolve(callee) == "inner3"
                }
                let outerCalls = body.filter { instr in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instr else { return false }
                    return interner.resolve(callee) == "outer3"
                }

                #expect(
                    innerCalls.count >= 1,
                    "Expected at least one inner3() call"
                )
                #expect(
                    outerCalls.count >= 1,
                    "Expected at least one outer3() call"
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

            do {
                let body = try findKIRFunctionBody(named: "loopWithContinue4", in: module, interner: interner)

                let cleanupCalls = body.enumerated().compactMap { (index, instr) -> (index: Int, canThrow: Bool)? in
                    guard case let .call(_, callee, _, _, canThrow, _, _, _) = instr,
                          interner.resolve(callee) == "cleanup4"
                    else { return nil }
                    return (index: index, canThrow: canThrow)
                }

                #expect(
                    cleanupCalls.count >= 1,
                    "Expected at least one inlined cleanup4() call for finally on continue"
                )

                let hasThrowAwareCleanup = cleanupCalls.contains { $0.canThrow }
                #expect(
                    hasThrowAwareCleanup,
                    "Inlined finally cleanup4() should be throw-aware for continue path"
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

            do {
                let body = try findKIRFunctionBody(named: "main5", in: module, interner: interner)

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
}
#endif
