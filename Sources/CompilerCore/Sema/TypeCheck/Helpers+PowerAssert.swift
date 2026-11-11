extension CallTypeChecker {
    /// Detects calls to functions configured for the `power-assert` plugin
    /// (e.g. `kotlin.assert(cond)`) and records AST capture points plus the
    /// matching 2-argument message overload for KIR lowering.
    func maybeRecordPowerAssertCall(
        callExprID: ExprID,
        chosenCallee: SymbolID,
        sema: SemaModule
    ) {
        guard !sema.powerAssertFunctions.isEmpty,
              let calleeSym = sema.symbols.symbol(chosenCallee)
        else { return }

        let interner = driver.interner
        let fqName = calleeSym.fqName.map(interner.resolve).joined(separator: ".")
        guard sema.powerAssertFunctions.contains(fqName) else { return }

        guard let expr = driver.ast.arena.expr(callExprID) else { return }
        let args: [CallArgument]
        let callRange: SourceRange
        switch expr {
        case let .call(_, _, callArgs, range):
            args = callArgs
            callRange = range
        case let .memberCall(_, _, _, callArgs, range):
            args = callArgs
            callRange = range
        default:
            return
        }

        // Only rewrite single-argument calls without an explicit lazyMessage
        guard args.count == 1 else { return }

        // Only rewrite user source calls (skip bundled stdlib source internals)
        if let origin = driver.sourceManager?.origin(of: callRange.start.file), origin != .user {
            return
        }

        // Look up the companion overload accepting `(arg0, lazyMessage: () -> Any/String)`
        guard let messageOverload = findPowerAssertMessageOverload(
            for: chosenCallee,
            fqNameParts: calleeSym.fqName,
            sema: sema
        ) else { return }

        let callText: String
        let baseOffset: Int
        if let sourceManager = driver.sourceManager {
            let sliced = String(sourceManager.slice(callRange))
            // Keep single-line representation cleanly aligned for diagram rendering
            callText = sliced.components(separatedBy: .newlines).first ?? sliced
            baseOffset = callRange.start.offset
        } else {
            callText = interner.resolve(calleeSym.name) + "(...)"
            baseOffset = callRange.start.offset
        }

        var captures: [PowerAssertCaptureExpr] = []
        collectPowerAssertCaptures(
            exprID: args[0].expr,
            baseOffset: baseOffset,
            callText: callText,
            sema: sema,
            into: &captures
        )

        sema.powerAssertCalls[callExprID] = PowerAssertCallInfo(
            originalCallee: chosenCallee,
            messageOverloadCallee: messageOverload,
            callLineText: callText,
            argExprID: args[0].expr,
            captureExprs: captures
        )
    }

    private func findPowerAssertMessageOverload(
        for originalCallee: SymbolID,
        fqNameParts: [InternedString],
        sema: SemaModule
    ) -> SymbolID? {
        guard let origSig = sema.symbols.functionSignature(for: originalCallee) else {
            return nil
        }
        let candidates = sema.symbols.lookupAll(fqName: fqNameParts).filter { $0 != originalCallee }
        for candidate in candidates {
            guard let sig = sema.symbols.functionSignature(for: candidate),
                  sig.parameterTypes.count == origSig.parameterTypes.count + 1,
                  sig.parameterTypes.first == origSig.parameterTypes.first,
                  let lastParamType = sig.parameterTypes.last,
                  case let .functionType(fnType) = sema.types.kind(of: lastParamType),
                  fnType.params.isEmpty
            else { continue }
            return candidate
        }
        return nil
    }

    private func collectPowerAssertCaptures(
        exprID: ExprID,
        baseOffset: Int,
        callText: String,
        sema: SemaModule,
        into captures: inout [PowerAssertCaptureExpr]
    ) {
        guard let expr = driver.ast.arena.expr(exprID),
              let range = driver.ast.arena.exprRange(exprID)
        else { return }

        // Only capture expressions whose start lies on the single-line call text
        let startCol = range.start.offset - baseOffset
        guard startCol >= 0, startCol < callText.count else { return }

        switch expr {
        case let .binary(op, lhs, rhs, _):
            if op == .logicalAnd || op == .logicalOr {
                // Short-circuit operators may skip RHS evaluation; capture only the overall result
                // to guarantee SSA dominance.
                let opCol = binaryOperatorColumn(lhs: lhs, rhs: rhs, baseOffset: baseOffset, callText: callText) ?? startCol
                captures.append(PowerAssertCaptureExpr(exprID: exprID, columnOffset: opCol))
            } else {
                collectPowerAssertCaptures(exprID: lhs, baseOffset: baseOffset, callText: callText, sema: sema, into: &captures)
                let opCol = binaryOperatorColumn(lhs: lhs, rhs: rhs, baseOffset: baseOffset, callText: callText) ?? startCol
                captures.append(PowerAssertCaptureExpr(exprID: exprID, columnOffset: opCol))
                collectPowerAssertCaptures(exprID: rhs, baseOffset: baseOffset, callText: callText, sema: sema, into: &captures)
            }

        case let .unaryExpr(_, operand, _):
            captures.append(PowerAssertCaptureExpr(exprID: exprID, columnOffset: startCol))
            collectPowerAssertCaptures(exprID: operand, baseOffset: baseOffset, callText: callText, sema: sema, into: &captures)

        case .nameRef:
            captures.append(PowerAssertCaptureExpr(exprID: exprID, columnOffset: startCol))

        case .call:
            captures.append(PowerAssertCaptureExpr(exprID: exprID, columnOffset: startCol))

        case let .memberCall(receiver, _, _, _, _):
            collectPowerAssertCaptures(exprID: receiver, baseOffset: baseOffset, callText: callText, sema: sema, into: &captures)
            let memberCol: Int = {
                if let recvRange = driver.ast.arena.exprRange(receiver) {
                    let afterRecv = recvRange.end.offset - baseOffset
                    if let dotIdx = callText.dropFirst(max(0, afterRecv)).firstIndex(of: ".") {
                        return callText.distance(from: callText.startIndex, to: dotIdx) + 1
                    }
                }
                return startCol
            }()
            if memberCol >= 0, memberCol < callText.count {
                captures.append(PowerAssertCaptureExpr(exprID: exprID, columnOffset: memberCol))
            }

        default:
            // Literals and complex control-flow constructs are skipped (literals are self-evident;
            // control flow branches may not dominate failure formatting).
            break
        }
    }

    private func binaryOperatorColumn(
        lhs: ExprID,
        rhs: ExprID,
        baseOffset: Int,
        callText: String
    ) -> Int? {
        guard let lhsRange = driver.ast.arena.exprRange(lhs),
              let rhsRange = driver.ast.arena.exprRange(rhs)
        else { return nil }
        let start = lhsRange.end.offset - baseOffset
        let end = rhsRange.start.offset - baseOffset
        guard start >= 0, end <= callText.count, start < end else { return nil }
        let utf8 = Array(callText.utf8)
        for i in start ..< end where i < utf8.count {
            if utf8[i] != UInt8(ascii: " ") && utf8[i] != UInt8(ascii: "\t") {
                return i
            }
        }
        return start
    }
}
