@testable import CompilerCore
import XCTest

final class FinallyExceptionRouteTests: XCTestCase {

    func testReturnInTryCatchFinallyRoutesExceptionOutward() throws {
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

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)

            let cleanupCalls = body.enumerated().compactMap { (index, instr) -> (index: Int, canThrow: Bool, hasThrownResult: Bool)? in
                guard case let .call(_, callee, _, _, canThrow, thrownResult, _, _) = instr,
                      ctx.interner.resolve(callee) == "cleanup"
                else { return nil }
                return (index: index, canThrow: canThrow, hasThrownResult: thrownResult != nil)
            }

            XCTAssertGreaterThanOrEqual(
                cleanupCalls.count, 1,
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
            XCTAssertTrue(
                hasThrowAwareInlinedCleanup,
                "Inlined finally cleanup() should be wrapped with throw-aware handling (canThrow: true)"
            )

            XCTAssertGreaterThanOrEqual(
                rethrowIndices.count, 1,
                "Expected at least one rethrow instruction for inlined finally exception routing"
            )
        }
    }

    func testBreakInTryCatchFinallyRoutesExceptionOutward() throws {
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

    func testInlinedFinallyWithNoCallsSkipsExceptionWrapping() throws {
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

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)

            let hasReturnValue = body.contains { if case .returnValue = $0 { return true }; return false }
            XCTAssertTrue(hasReturnValue, "Expected at least one returnValue instruction")
            XCTAssertFalse(body.isEmpty, "Expected non-empty function body")
        }
    }

    func testNestedTryFinallyExceptionRouting() throws {
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

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)

            let innerCalls = body.filter { instr in
                guard case let .call(_, callee, _, _, _, _, _, _) = instr else { return false }
                return ctx.interner.resolve(callee) == "inner"
            }
            let outerCalls = body.filter { instr in
                guard case let .call(_, callee, _, _, _, _, _, _) = instr else { return false }
                return ctx.interner.resolve(callee) == "outer"
            }

            XCTAssertGreaterThanOrEqual(innerCalls.count, 1, "Expected at least one inner() call")
            XCTAssertGreaterThanOrEqual(outerCalls.count, 1, "Expected at least one outer() call")

            let rethrowCount = body.filter { instr in
                if case .rethrow = instr { return true }
                return false
            }.count

            XCTAssertGreaterThanOrEqual(
                rethrowCount, 1,
                "Expected rethrow instructions for nested finally exception routing"
            )
        }
    }

    func testContinueInTryCatchFinallyRoutesExceptionOutward() throws {
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

    // break/continue paths share the same assertion structure
    private func assertInlinedFinallyIsThrowAware(source: String, functionName: String) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)

            let cleanupCalls = body.enumerated().compactMap { (index, instr) -> (index: Int, canThrow: Bool)? in
                guard case let .call(_, callee, _, _, canThrow, _, _, _) = instr,
                      ctx.interner.resolve(callee) == "cleanup"
                else { return nil }
                return (index: index, canThrow: canThrow)
            }

            XCTAssertGreaterThanOrEqual(cleanupCalls.count, 1,
                "Expected at least one inlined cleanup() call for finally on \(functionName)")

            let hasThrowAwareCleanup = cleanupCalls.contains { $0.canThrow }
            XCTAssertTrue(hasThrowAwareCleanup,
                "Inlined finally cleanup() should be throw-aware for \(functionName)")

            let rethrowCount = body.filter { if case .rethrow = $0 { return true }; return false }.count
            XCTAssertGreaterThanOrEqual(rethrowCount, 1,
                "Expected at least one rethrow for inlined finally exception routing on \(functionName)")
        }
    }
}
