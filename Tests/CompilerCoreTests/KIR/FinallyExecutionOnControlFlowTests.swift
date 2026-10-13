#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct FinallyExecutionOnControlFlowTests {

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
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)

        let cleanup = try findKIRFunction(named: "cleanup", in: module, interner: ctx.interner)
        let cleanupCallIndices = kirCalls(to: cleanup.symbol, in: body).map(\.index)
        let returnValueIndices = body.indices.filter { index in
            if case .returnValue = body[index] { return true }
            return false
        }

        #expect(
            cleanupCallIndices.count >= 1,
            "Expected at least one inlined cleanup() call for finally block"
        )
        #expect(
            returnValueIndices.count >= 1,
            "Expected at least one returnValue instruction"
        )

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
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "doWork", in: module, interner: ctx.interner)

        let cleanup = try findKIRFunction(named: "cleanup", in: module, interner: ctx.interner)
        let cleanupCallIndices = kirCalls(to: cleanup.symbol, in: body).map(\.index)
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

    @Test func testReturnBareLocalInsideTryFinallyDoesNotObserveFinallyMutation() throws {
        // `return i` inside a try must snapshot `i`'s value before the
        // finally block runs. `nameRef` resolves a bare variable read to
        // the variable's own storage register (not a copy), so without a
        // snapshot the register `.returnValue` reads from is the same one
        // the finally's `i = 99` reassignment (`.copy(..., to: <that
        // register>)`) writes into.
        let source = """
        fun f4(): Int {
            var i = 0
            try {
                i = 1
                return i
            } finally {
                i = 99
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "f4", in: module, interner: ctx.interner)

        // Locate the constant 99 produced for the finally's `i = 99`, then
        // the copy that writes it into `i`'s storage register.
        let ninetyNineExprs: Set<KIRExprID> = Set(body.compactMap { instr -> KIRExprID? in
            guard case let .constValue(result, value) = instr, value == .intLiteral(99) else { return nil }
            return result
        })
        let iStorageRegisters: [KIRExprID] = body.compactMap { instr -> KIRExprID? in
            guard case let .copy(from, to) = instr, ninetyNineExprs.contains(from) else { return nil }
            return to
        }
        #expect(!iStorageRegisters.isEmpty, "Expected to find the copy lowering `i = 99` in the finally block")

        let returnValueOperands: [KIRExprID] = body.compactMap { instr -> KIRExprID? in
            guard case let .returnValue(value) = instr else { return nil }
            return value
        }
        #expect(!returnValueOperands.isEmpty, "Expected at least one returnValue instruction")

        for iStorage in iStorageRegisters {
            #expect(
                !returnValueOperands.contains(iStorage),
                "returnValue must not alias `i`'s storage register, or it would observe the finally's `i = 99` mutation"
            )
        }
    }

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
        let ctx = makeContextFromSource(source)
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
        let cleanup = try findKIRFunction(named: "cleanup", in: module, interner: ctx.interner)
        let cleanupCallIndices = kirCalls(to: cleanup.symbol, in: body).map(\.index)

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
        let ctx = makeContextFromSource(source)
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

        let cleanup = try findKIRFunction(named: "cleanup", in: module, interner: ctx.interner)
        let cleanupCallIndices = kirCalls(to: cleanup.symbol, in: body).map(\.index)

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
