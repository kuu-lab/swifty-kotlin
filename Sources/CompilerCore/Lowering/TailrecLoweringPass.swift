
/// Chosen to avoid collision with user labels and coroutine dispatch labels.
let tailrecLoopLabelBase: Int32 = 9000

final class TailrecLoweringPass: LoweringPass {
    static let name = "TailrecLowering"
    static let requiredStage: KIRStage = .raw
    static let producedStage: KIRStage = .tailrecLowered

    private struct TailrecFunctionIdentity {
        let symbol: SymbolID
    }

    func shouldRun(module: KIRModule, ctx _: KIRContext) -> Bool {
        module.ensureFeaturesScanned()
        return module.features.contains(.hasTailrecFunction)
    }

    func run(module: KIRModule, ctx _: KIRContext) throws {
        var nextLoopLabel = tailrecLoopLabelBase

        module.arena.transformFunctions { function in
            guard function.isTailrec else { return function }

            // Avoid label collision with the function's existing labels.
            let maxExistingLabel = function.body.compactMap { instruction -> Int32? in
                if case let .label(id) = instruction { return id }
                return nil
            }.max() ?? (tailrecLoopLabelBase - 1)

            let loopLabel = max(nextLoopLabel, maxExistingLabel + 1)
            nextLoopLabel = loopLabel + 1

            let functionIdentity = TailrecFunctionIdentity(
                symbol: function.symbol
            )
            var updated = function
            let rewrittenBody = rewriteTailCalls(
                body: function.body,
                functionIdentity: functionIdentity,
                params: function.params,
                loopLabel: loopLabel,
                arena: module.arena
            )
            // The rewrite changes instruction count, so the old parallel
            // array is stale.  Use the function-level sourceRange as a
            // conservative location for every synthesised instruction.
            updated.replaceBody(
                rewrittenBody,
                locations: Array(repeating: function.sourceRange, count: rewrittenBody.count)
            )
            return updated
        }

        module.recordLowering(Self.name)
    }

    /// A non-zero mask means the `$default` stub would evaluate default
    /// expressions to fill in missing arguments.  At this lowering stage
    /// we don't have access to those default expressions, so keeping the
    /// parameter's value from the previous iteration would silently
    /// miscompile.
    private func canOptimizeDefaultStubCall(
        symbol: SymbolID?,
        functionIdentity: TailrecFunctionIdentity,
        arguments: [KIRExprID],
        body: [KIRInstruction],
        callIndex: Int,
        parameterCount: Int,
        arena: KIRArena
    ) -> (canOptimize: Bool, defaultMask: Int64?) {
        let isDefault = isDefaultStubCall(symbol: symbol, functionIdentity: functionIdentity)
        guard isDefault else {
            return (canOptimize: true, defaultMask: nil)
        }
        let mask = extractDefaultMask(
            arguments: arguments, body: body, callIndex: callIndex,
            parameterCount: parameterCount, arena: arena
        )
        guard let mask, mask == 0 else {
            return (canOptimize: false, defaultMask: mask)
        }
        return (canOptimize: true, defaultMask: mask)
    }

    private func rewriteTailCalls(
        body: [KIRInstruction],
        functionIdentity: TailrecFunctionIdentity,
        params: [KIRParameter],
        loopLabel: Int32,
        arena: KIRArena
    ) -> [KIRInstruction] {
        var result = KIRLoweringEmitContext()
        result.instructions.reserveCapacity(body.count + 2)
        let loopInsertIndex = loopEntryIndex(body: body, params: params)
        let canonicalParamExprs = canonicalParameterExprs(
            body: Array(body[..<loopInsertIndex]),
            params: params
        )
        if loopInsertIndex > 0 {
            result.append(contentsOf: body[..<loopInsertIndex])
        }
        result.append(.label(loopLabel))

        // Pre-compute receiver offset once per function instead of per
        // call site.  The receiver is a function-level property, so this
        // avoids repeated SyntheticSymbolScheme lookups when a function
        // contains multiple tail-call rewrites.
        let receiverOffset: Int = {
            let receiverSymbol = SyntheticSymbolScheme.receiverParameterSymbol(
                for: functionIdentity.symbol
            )
            return (!params.isEmpty && params[0].symbol == receiverSymbol) ? 1 : 0
        }()

        var instructionIndex = loopInsertIndex
        var emittedTailJump = false
        while instructionIndex < body.count {
            let instruction = body[instructionIndex]

            if case .beginBlock = instruction {
                result.append(instruction)
                instructionIndex += 1
                continue
            }

            if case let .call(symbol, _, arguments, callResult, _, _, _, _) = instruction,
               isSelfRecursiveCall(symbol: symbol, functionIdentity: functionIdentity),
               tailReturnIndex(body: body, callIndex: instructionIndex, callResult: callResult) != nil
            {
                let check = canOptimizeDefaultStubCall(
                    symbol: symbol, functionIdentity: functionIdentity,
                    arguments: arguments, body: body,
                    callIndex: instructionIndex, parameterCount: params.count, arena: arena
                )
                guard check.canOptimize else {
                    result.append(instruction)
                    instructionIndex += 1
                    continue
                }
                emitParameterReassignment(
                    arguments: arguments,
                    params: params,
                    canonicalParamExprs: canonicalParamExprs,
                    defaultMask: check.defaultMask,
                    receiverOffset: receiverOffset,
                    arena: arena,
                    result: &result
                )
                result.append(.jump(loopLabel))
                emittedTailJump = true
                // The straight-line run behind the call (result copies, the
                // jump to the join label, or the return itself) is now
                // unreachable and would read the call result that no longer
                // exists, so drop it. Everything from the next label on is kept:
                // other branches may still reach it.
                instructionIndex += 1
                while instructionIndex < body.count {
                    switch body[instructionIndex] {
                    case .label, .beginBlock, .endBlock:
                        break
                    default:
                        instructionIndex += 1
                        continue
                    }
                    break
                }
                continue
            }

            result.append(instruction)
            instructionIndex += 1
        }

        // Safety: if we emitted a jump but somehow the label is missing
        // (should not happen with the unconditional insert above), leave
        // the body unchanged to avoid producing invalid KIR.
        if emittedTailJump, !result.contains(where: { if case .label(loopLabel) = $0 { return true }; return false }) {
            return body
        }

        return emittedTailJump ? pruneUnreachableJoins(result.instructions) : result.instructions
    }

    /// Tail-call replacement can make the remaining instructions after an
    /// unconditional terminator unreachable, including expression-join code
    /// emitted after a throwing branch. Drop that code through unreferenced
    /// labels until reaching a label with an incoming jump. Keep block markers
    /// so the surrounding KIR structure remains balanced.
    private func pruneUnreachableJoins(_ instructions: [KIRInstruction]) -> [KIRInstruction] {
        var current = instructions
        var changed = true
        while changed {
            changed = false
            var targets: Set<Int32> = []
            for instruction in current {
                switch instruction {
                case let .jump(target), let .jumpIfEqual(_, _, target), let .jumpIfNotNull(_, target):
                    targets.insert(target)
                default:
                    break
                }
            }
            var pruned: [KIRInstruction] = []
            pruned.reserveCapacity(current.count)
            var isUnreachable = false
            for instruction in current {
                if isUnreachable {
                    switch instruction {
                    case let .label(id) where targets.contains(id):
                        pruned.append(instruction)
                        isUnreachable = false
                    case .beginBlock, .endBlock:
                        pruned.append(instruction)
                    default:
                        changed = true
                    }
                    continue
                }

                pruned.append(instruction)
                if isTerminator(instruction) {
                    isUnreachable = true
                }
            }
            current = pruned
        }
        return current
    }

    private func isTerminator(_ instruction: KIRInstruction) -> Bool {
        switch instruction {
        case .jump, .returnValue, .returnUnit, .rethrow, .nonLocalReturn:
            true
        default:
            false
        }
    }

    /// When a recursive call uses default arguments, the KIR emitter routes
    /// through `foo$default` which carries a different symbol; without this
    /// check, tailrec optimization would miss those calls (LOWER-005).
    private func isSelfRecursiveCall(
        symbol: SymbolID?,
        functionIdentity: TailrecFunctionIdentity
    ) -> Bool {
        guard let symbol else { return false }
        if symbol == functionIdentity.symbol { return true }
        let defaultStub = SyntheticSymbolScheme.defaultStubSymbol(for: functionIdentity.symbol)
        return symbol == defaultStub
    }

    private func isDefaultStubCall(
        symbol: SymbolID?,
        functionIdentity: TailrecFunctionIdentity
    ) -> Bool {
        guard let symbol else { return false }
        return symbol == SyntheticSymbolScheme.defaultStubSymbol(for: functionIdentity.symbol)
    }

    /// Default masks follow the target's ordinary parameters and are expected
    /// to be constant integer literals.
    ///
    /// The `callIndex` parameter limits the slow-path scan to instructions
    /// that precede the call site, so we only pick up definitions that
    /// dominate the use.
    private func extractDefaultMask(
        arguments: [KIRExprID],
        body: [KIRInstruction],
        callIndex: Int,
        parameterCount: Int,
        arena: KIRArena
    ) -> Int64? {
        guard arguments.count > parameterCount else { return nil }
        let maskExprIDs = arguments.dropFirst(parameterCount)
        guard !maskExprIDs.isEmpty else { return nil }
        var maskValues: [Int64] = []
        for maskExprID in maskExprIDs {
            if let exprKind = arena.expr(maskExprID), case let .intLiteral(mask) = exprKind {
                maskValues.append(mask)
                continue
            }
            var found: Int64?
            // Scanning only instructions before `callIndex` ensures the
            // definition dominates the use. Stop at control-flow boundaries
            // so a linear backward scan cannot cross branches.
            for i in stride(from: callIndex - 1, through: 0, by: -1) {
                let inst = body[i]
                switch inst {
                case .label, .jump, .jumpIfEqual, .jumpIfNotNull:
                    return nil
                default:
                    break
                }
                if case let .constValue(result, .intLiteral(value)) = inst,
                   result == maskExprID
                {
                    found = value
                    break
                }
            }
            guard let found else { return nil }
            maskValues.append(found)
        }
        return maskValues.first(where: { $0 != 0 }) ?? 0
    }

    /// Expression bodies (`= if (c) acc else f(..)`, `= when { .. }`) lower to
    /// `call -> copy(callResult, joinTemp) -> jump/label ... -> returnValue(joinTemp)`,
    /// so only `label`, `jump`, and `copy` of the call result (or of a value
    /// already aliasing it) may sit between the call and the return. Unit-valued
    /// statement branches can also materialize a fresh `unit` constant and copy
    /// it into the join temporary before `returnUnit`; those pure instructions
    /// do not make the recursive call non-tail. Any other instruction (a store,
    /// a call, a conditional jump, exception plumbing of `try`/`finally`) means
    /// work remains after the call and the call is not a tail call.
    private func tailReturnIndex(
        body: [KIRInstruction],
        callIndex: Int,
        callResult: KIRExprID?
    ) -> Int? {
        var aliases: Set<KIRExprID> = []
        var unitValues: Set<KIRExprID> = []
        if let callResult { aliases.insert(callResult) }
        var visited: Set<Int> = []
        var index = callIndex + 1
        while index < body.count, visited.insert(index).inserted {
            switch body[index] {
            case .label, .beginBlock, .endBlock:
                index += 1
            case let .jump(target):
                guard let targetIndex = body.firstIndex(where: {
                    if case let .label(id) = $0 { return id == target }
                    return false
                }) else { return nil }
                index = targetIndex
            case let .copy(from, to):
                if aliases.contains(from) {
                    aliases.insert(to)
                } else if unitValues.contains(from) {
                    unitValues.insert(to)
                } else {
                    return nil
                }
                index += 1
            case let .constValue(result, .unit):
                unitValues.insert(result)
                index += 1
            case let .returnValue(value):
                return aliases.contains(value) ? index : nil
            case .returnUnit:
                // A self-call followed by `returnUnit` can only sit in a
                // Unit function; its (Unit) result, if materialized by an
                // `if` statement's join copy, carries no value to preserve.
                return index
            default:
                return nil
            }
        }
        return nil
    }

    /// When `defaultMask` is non-nil, it is expected to be 0 (all
    /// arguments explicitly provided). The caller extracts every trailing
    /// mask word and skips tailrec for non-zero masks because we cannot inline
    /// default expressions at this lowering stage.
    ///
    /// The default mask bits are 0-indexed on *value parameter* positions
    /// (excluding the receiver).  When the function has a receiver
    /// parameter (detected via `SyntheticSymbolScheme`), the receiver
    /// occupies index 0 in both `params` and `arguments` but is not
    /// counted in the mask.  `receiverOffset` (0 or 1) is pre-computed
    /// once per function in `rewriteTailCalls` and passed in here so
    /// that we avoid repeated `SyntheticSymbolScheme` lookups when a
    /// function has multiple tail-call sites.
    private func emitParameterReassignment(
        arguments: [KIRExprID],
        params: [KIRParameter],
        canonicalParamExprs: [SymbolID: KIRExprID],
        defaultMask: Int64? = nil,
        receiverOffset: Int,
        arena: KIRArena,
        result: inout KIRLoweringEmitContext
    ) {
        // Only copy the first `params.count` arguments; $default calls
        // carry trailing reified-type tokens and mask words that must not
        // participate in parameter reassignment.
        let effectiveCount = min(arguments.count, params.count)

        // First, copy arguments into fresh temporaries to avoid
        // overwriting a parameter that is used in a later argument expression.
        var temporaries: [KIRExprID] = []
        temporaries.reserveCapacity(effectiveCount)
        for i in 0 ..< effectiveCount {
            // Skip sentinel arguments whose default mask bit is set.
            // The mask is indexed on value-parameter positions (excluding
            // the receiver), so subtract `receiverOffset`. The caller skips
            // tailrec for any non-zero word, leaving this path with a zero
            // mask; retain the conservative handling for defense-in-depth.
            if let mask = defaultMask {
                let maskBitIndex = i - receiverOffset
                if maskBitIndex >= 0 {
                    if maskBitIndex >= Int64.bitWidth {
                        // Out-of-range bit index — conservatively treat
                        // as non-defaulted (copy the argument through).
                    } else if (mask >> maskBitIndex) & 1 != 0 {
                        temporaries.append(.invalid)
                        continue
                    }
                }
            }
            let arg = arguments[i]
            let argType = arena.exprType(arg)
            let temp = arena.appendTemporary(type: argType)
            result.append(.copy(from: arg, to: temp))
            temporaries.append(temp)
        }

        for (index, param) in params.enumerated() {
            guard index < temporaries.count else { break }
            let temp = temporaries[index]
            guard temp != .invalid else { continue }
            let paramExpr = canonicalParamExprs[param.symbol]
                ?? arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            result.append(.copy(from: temp, to: paramExpr))
        }
    }

    private func canonicalParameterExprs(
        body: [KIRInstruction],
        params: [KIRParameter]
    ) -> [SymbolID: KIRExprID] {
        let parameterSymbols = Set(params.map(\.symbol))
        var result: [SymbolID: KIRExprID] = [:]
        for instruction in body {
            guard case let .constValue(exprID, .symbolRef(symbol)) = instruction,
                  parameterSymbols.contains(symbol),
                  result[symbol] == nil
            else {
                continue
            }
            result[symbol] = exprID
        }
        return result
    }

    private func loopEntryIndex(body: [KIRInstruction], params: [KIRParameter]) -> Int {
        let parameterSymbols = Set(params.map(\.symbol))
        var index = 0
        if index < body.count, case .beginBlock = body[index] {
            index += 1
        }
        while index < body.count {
            guard case let .constValue(_, .symbolRef(symbol)) = body[index],
                  parameterSymbols.contains(symbol)
            else {
                break
            }
            index += 1
        }
        return index
    }
}
