#if canImport(Testing)
@testable import CompilerCore
import Testing

/// CODE-001: Regression tests ensuring `finally` blocks execute on
/// `return`, `break`, and `continue` inside try-finally.
@Suite
struct FinallyExecutionOnControlFlowTests {

    @Test func testFinallyExecutesBeforeControlFlowTransfer() throws {
        let sources = [
            // return inside try-finally
            """
            package sample0

            fun cleanup0(): Unit {}
            fun compute0(): Int {
                try {
                    return 42
                } finally {
                    cleanup0()
                }
            }
            """,
            // return unit inside try-finally
            """
            package sample1

            fun cleanup1(): Unit {}
            fun doWork1(): Unit {
                try {
                    return
                } finally {
                    cleanup1()
                }
            }
            """,
            // break inside try-finally
            """
            package sample2

            fun cleanup2(): Unit {}
            fun loopWithBreak2(): Unit {
                while (true) {
                    try {
                        break
                    } finally {
                        cleanup2()
                    }
                }
            }
            """,
            // continue inside try-finally
            """
            package sample3

            fun cleanup3(): Unit {}
            fun counter3(): Boolean = false
            fun loopWithContinue3(): Unit {
                while (counter3()) {
                    try {
                        continue
                    } finally {
                        cleanup3()
                    }
                }
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            // sample0: return value
            do {
                let body = try findKIRFunctionBody(named: "compute0", in: module, interner: interner)
                let cleanupCallIndices = body.indices.filter { index in
                    guard case let .call(_, callee, _, _, _, _, _, _) = body[index] else { return false }
                    return interner.resolve(callee) == "cleanup0"
                }
                let returnValueIndices = body.indices.filter { index in
                    if case .returnValue = body[index] { return true }
                    return false
                }

                #expect(cleanupCallIndices.count >= 1, "Expected at least one inlined cleanup0() call for finally block")
                #expect(returnValueIndices.count >= 1, "Expected at least one returnValue instruction")

                let hasCleanupBeforeReturn = cleanupCallIndices.contains { cleanupIndex in
                    returnValueIndices.contains { returnIndex in cleanupIndex < returnIndex }
                }
                #expect(hasCleanupBeforeReturn, "finally block (cleanup0()) must execute before returnValue")
            }

            // sample1: return unit
            do {
                let body = try findKIRFunctionBody(named: "doWork1", in: module, interner: interner)
                let cleanupCallIndices = body.indices.filter { index in
                    guard case let .call(_, callee, _, _, _, _, _, _) = body[index] else { return false }
                    return interner.resolve(callee) == "cleanup1"
                }
                let returnUnitIndices = body.indices.filter { index in
                    if case .returnUnit = body[index] { return true }
                    return false
                }

                #expect(cleanupCallIndices.count >= 1, "Expected at least one inlined cleanup1() for finally on return unit")

                let hasCleanupBeforeReturn = cleanupCallIndices.contains { cleanupIndex in
                    returnUnitIndices.contains { returnIndex in cleanupIndex < returnIndex }
                }
                #expect(hasCleanupBeforeReturn, "finally block (cleanup1()) must execute before returnUnit")
            }

            // sample2: break
            do {
                let body = try findKIRFunctionBody(named: "loopWithBreak2", in: module, interner: interner)

                let firstLabelIndex = body.firstIndex(where: { if case .label = $0 { return true }; return false })
                var conditionLabel: Int32?
                if let idx = firstLabelIndex, case let .label(l) = body[idx] {
                    conditionLabel = l
                }

                let cleanupCallIndices = body.indices.filter { index in
                    guard case let .call(_, callee, _, _, _, _, _, _) = body[index] else { return false }
                    return interner.resolve(callee) == "cleanup2"
                }

                let breakJumpIndices = body.indices.filter { index in
                    guard case let .jump(target) = body[index] else { return false }
                    return target != conditionLabel
                }

                #expect(cleanupCallIndices.count >= 1, "Expected at least one inlined cleanup2() call for finally block on break")
                #expect(breakJumpIndices.count >= 1, "Expected at least one jump instruction for break")

                let hasCleanupBeforeBreakJump = cleanupCallIndices.contains { cleanupIndex in
                    breakJumpIndices.contains { jumpIndex in cleanupIndex < jumpIndex }
                }
                #expect(hasCleanupBeforeBreakJump, "finally block (cleanup2()) must execute before the break jump")
            }

            // sample3: continue
            do {
                let body = try findKIRFunctionBody(named: "loopWithContinue3", in: module, interner: interner)

                var conditionLabel: Int32?
                for instr in body {
                    if case let .label(l) = instr {
                        conditionLabel = l
                        break
                    }
                }

                let cleanupCallIndices = body.indices.filter { index in
                    guard case let .call(_, callee, _, _, _, _, _, _) = body[index] else { return false }
                    return interner.resolve(callee) == "cleanup3"
                }

                let continueJumpIndices: [Int]
                if let target = conditionLabel {
                    continueJumpIndices = body.indices.filter { index in
                        guard case let .jump(dest) = body[index] else { return false }
                        return dest == target
                    }
                } else {
                    continueJumpIndices = body.indices.filter { index in
                        if case .jump = body[index] { return true }
                        return false
                    }
                }

                #expect(cleanupCallIndices.count >= 1, "Expected at least one inlined cleanup3() call for finally block on continue")
                #expect(continueJumpIndices.count >= 1, "Expected at least one jump instruction for continue")

                let hasCleanupBeforeContinueJump = cleanupCallIndices.contains { cleanupIndex in
                    continueJumpIndices.contains { jumpIndex in cleanupIndex < jumpIndex }
                }
                #expect(hasCleanupBeforeContinueJump, "finally block (cleanup3()) must execute before the continue jump")
            }
        }
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
