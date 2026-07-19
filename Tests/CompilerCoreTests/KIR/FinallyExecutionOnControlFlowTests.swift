#if canImport(Testing)
@testable import CompilerCore
import Testing

/// CODE-001: Regression tests ensuring `finally` blocks execute on
/// `return`, `break`, and `continue` inside try-finally.
@Suite
struct FinallyExecutionOnControlFlowTests {

    // MARK: - return inside try-finally

    @Test func testReturnInsideTryFinallyInlinesFinallyBeforeReturn() throws {
        let source = """
        fun cleanup(): Unit {}
        fun compute(): Int {
            try {
                return 42
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

            // The `return 42` path should call cleanup() *before* the returnValue
            // instruction. Find all cleanup calls and all returnValue instructions.
            let cleanupCallIndices = body.indices.filter { index in
                guard case let .call(_, callee, _, _, _, _, _, _) = body[index] else { return false }
                return ctx.interner.resolve(callee) == "cleanup"
            }
            let returnValueIndices = body.indices.filter { index in
                if case .returnValue = body[index] { return true }
                return false
            }

            // There should be at least one cleanup call inlined before a return.
            #expect(
                cleanupCallIndices.count >= 1,
                "Expected at least one inlined cleanup() call for finally block"
            )
            #expect(
                returnValueIndices.count >= 1,
                "Expected at least one returnValue instruction"
            )

            // At least one cleanup call should appear before a returnValue instruction.
            let hasCleanupBeforeReturn = cleanupCallIndices.contains { cleanupIndex in
                returnValueIndices.contains { returnIndex in
                    cleanupIndex < returnIndex
                }
            }
            #expect(
                hasCleanupBeforeReturn,
                "finally block (cleanup()) must execute before returnValue"
            )
        }
    }

    @Test func testReturnUnitInsideTryFinallyInlinesFinallyBeforeReturn() throws {
        let source = """
        fun cleanup(): Unit {}
        fun doWork(): Unit {
            try {
                return
            } finally {
                cleanup()
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "doWork", in: module, interner: ctx.interner)

            let cleanupCallIndices = body.indices.filter { index in
                guard case let .call(_, callee, _, _, _, _, _, _) = body[index] else { return false }
                return ctx.interner.resolve(callee) == "cleanup"
            }
            let returnUnitIndices = body.indices.filter { index in
                if case .returnUnit = body[index] { return true }
                return false
            }

            #expect(
                cleanupCallIndices.count >= 1,
                "Expected at least one inlined cleanup() for finally on return unit"
            )

            let hasCleanupBeforeReturn = cleanupCallIndices.contains { cleanupIndex in
                returnUnitIndices.contains { returnIndex in
                    cleanupIndex < returnIndex
                }
            }
            #expect(
                hasCleanupBeforeReturn,
                "finally block (cleanup()) must execute before returnUnit"
            )
        }
    }

    // MARK: - break inside try-finally

    @Test func testBreakInsideTryFinallyInlinesFinallyBeforeBreak() throws {
        let source = """
        fun cleanup(): Unit {}
        fun loopWithBreak(): Unit {
            while (true) {
                try {
                    break
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

            // Find the first label defined in the body (the while-condition label).
            let firstLabelIndex = body.firstIndex(where: { if case .label = $0 { return true }; return false })
            var conditionLabel: Int32?
            if let idx = firstLabelIndex, case let .label(l) = body[idx] {
                conditionLabel = l
            }

            // cleanup() should appear in the lowered body before the break jump.
            let cleanupCallIndices = body.indices.filter { index in
                guard case let .call(_, callee, _, _, _, _, _, _) = body[index] else { return false }
                return ctx.interner.resolve(callee) == "cleanup"
            }

            // Find jump instructions whose target is NOT the continue (condition) label,
            // i.e. break jumps.  Match by specific target label to avoid false positives
            // from unrelated jumps (back-edges, condition dispatch, etc.).
            let breakJumpIndices = body.indices.filter { index in
                guard case let .jump(target) = body[index] else { return false }
                return target != conditionLabel
            }

            #expect(
                cleanupCallIndices.count >= 1,
                "Expected at least one inlined cleanup() call for finally block on break"
            )
            #expect(
                breakJumpIndices.count >= 1,
                "Expected at least one jump instruction for break"
            )

            // At least one cleanup call must appear before a break jump.
            // Note: with CODE-001 exception routing, the inlined finally may
            // include rethrow labels between the cleanup call and the break
            // jump, so we no longer require them to be in the same basic block.
            let hasCleanupBeforeBreakJump = cleanupCallIndices.contains { cleanupIndex in
                breakJumpIndices.contains { jumpIndex in
                    cleanupIndex < jumpIndex
                }
            }
            #expect(
                hasCleanupBeforeBreakJump,
                "finally block (cleanup()) must execute before the break jump"
            )
        }
    }

    // MARK: - continue inside try-finally

    @Test func testContinueInsideTryFinallyInlinesFinallyBeforeContinue() throws {
        let source = """
        fun cleanup(): Unit {}
        fun counter(): Boolean = false
        fun loopWithContinue(): Unit {
            while (counter()) {
                try {
                    continue
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

            // Identify the continue target label: in a while loop the continue
            // label is the first label defined in the function body (the loop
            // condition check label).
            var conditionLabel: Int32?
            for instr in body {
                if case let .label(l) = instr {
                    conditionLabel = l
                    break
                }
            }

            let cleanupCallIndices = body.indices.filter { index in
                guard case let .call(_, callee, _, _, _, _, _, _) = body[index] else { return false }
                return ctx.interner.resolve(callee) == "cleanup"
            }

            // Find jump instructions whose target IS the continue (condition) label.
            // This specifically identifies continue transfers, excluding break jumps
            // and other control flow.
            let continueJumpIndices: [Int]
            if let target = conditionLabel {
                continueJumpIndices = body.indices.filter { index in
                    guard case let .jump(dest) = body[index] else { return false }
                    return dest == target
                }
            } else {
                // Fallback: if we cannot identify the condition label, match any jump.
                continueJumpIndices = body.indices.filter { index in
                    if case .jump = body[index] { return true }
                    return false
                }
            }

            #expect(
                cleanupCallIndices.count >= 1,
                "Expected at least one inlined cleanup() call for finally block on continue"
            )
            #expect(
                continueJumpIndices.count >= 1,
                "Expected at least one jump instruction for continue"
            )

            // At least one cleanup call must appear before a continue jump.
            // Note: with CODE-001 exception routing, the inlined finally may
            // include rethrow labels between the cleanup call and the continue
            // jump, so we no longer require them to be in the same basic block.
            let hasCleanupBeforeContinueJump = cleanupCallIndices.contains { cleanupIndex in
                continueJumpIndices.contains { jumpIndex in
                    cleanupIndex < jumpIndex
                }
            }
            #expect(
                hasCleanupBeforeContinueJump,
                "finally block (cleanup()) must execute before the continue jump"
            )
        }
    }

    // MARK: - Context stack push/pop

    @Test func testFinallyBlockStackPushPopSymmetry() {
        let ctx = KIRLoweringContext()
        #expect(ctx.enclosingFinallyBlocks().isEmpty)

        let expr1 = ExprID(rawValue: 100)
        let expr2 = ExprID(rawValue: 200)
        ctx.pushFinallyBlock(expr1)
        ctx.pushFinallyBlock(expr2)
        #expect(ctx.enclosingFinallyBlocks().count == 2)

        let popped = ctx.popFinallyBlock()
        #expect(popped == expr2)
        #expect(ctx.enclosingFinallyBlocks().count == 1)

        let popped2 = ctx.popFinallyBlock()
        #expect(popped2 == expr1)
        #expect(ctx.enclosingFinallyBlocks().isEmpty)
    }

    @Test func testResetScopeForFunctionClearsFinallyBlockStack() {
        let ctx = KIRLoweringContext()
        ctx.pushFinallyBlock(ExprID(rawValue: 50))
        ctx.resetScopeForFunction()
        #expect(ctx.enclosingFinallyBlocks().isEmpty)
    }

    @Test func testScopeSaveRestorePreservesFinallyBlockStack() {
        let ctx = KIRLoweringContext()
        let expr1 = ExprID(rawValue: 42)
        ctx.pushFinallyBlock(expr1)

        let snapshot = ctx.saveScope()
        ctx.resetScopeForFunction()
        #expect(ctx.enclosingFinallyBlocks().isEmpty)

        ctx.restoreScope(snapshot)
        #expect(ctx.enclosingFinallyBlocks().count == 1)
        #expect(ctx.enclosingFinallyBlocks().first == expr1)
    }

    @Test func testFinallyBlockScopeFilteringSkipsInnerTryForBreak() {
        // Simulates: while { try { break } finally { cleanup() } }
        // The finally was pushed AFTER the loop, so break exits the try scope
        // and should inline the finally block.
        let ctx = KIRLoweringContext()
        ctx.pushLoopControl(continueLabel: 100, breakLabel: 101, name: nil)
        ctx.pushFinallyBlock(ExprID(rawValue: 42))

        let targetDepth = ctx.breakTargetLoopDepth(for: nil)
        let blocks = ctx.enclosingFinallyBlocksForBreakOrContinue(targetLoopDepth: targetDepth)
        #expect(blocks.count == 1, "break exiting try scope should inline the finally block")

        ctx.popFinallyBlock()
        ctx.popLoopControl()
    }

    @Test func testFinallyBlockScopeFilteringSkipsWhenLoopInsideTry() {
        // Simulates: try { while { break } } finally { cleanup() }
        // The finally was pushed BEFORE the loop, so break stays within
        // the try scope and should NOT inline the finally block.
        let ctx = KIRLoweringContext()
        ctx.pushFinallyBlock(ExprID(rawValue: 42))
        ctx.pushLoopControl(continueLabel: 200, breakLabel: 201, name: nil)

        let targetDepth = ctx.breakTargetLoopDepth(for: nil)
        let blocks = ctx.enclosingFinallyBlocksForBreakOrContinue(targetLoopDepth: targetDepth)
        #expect(blocks.count == 0, "break inside try scope should NOT inline the finally block")

        ctx.popLoopControl()
        ctx.popFinallyBlock()
    }
}
#endif
