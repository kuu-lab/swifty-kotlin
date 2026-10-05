extension CoroutineLoweringPass {
    private func isFreshFlowCall(
        _ instruction: KIRInstruction,
        freshFunctions: Set<SymbolID>,
        constants: [KIRExprID: Int64],
        module: KIRModule,
        ctx: KIRContext
    ) -> KIRExprID? {
        guard case let .call(symbol, callee, arguments, result, _, _, _, _) = instruction else { return nil }
        let name = ctx.interner.resolve(callee)
        let factories: Set<String> = [
            "kk_flow_create", "kk_channel_flow_create", "kk_callback_flow_create",
            "__kk_flow_zip", "__kk_flow_combine", "__kk_flow_merge",
            "__kk_flow_flat_map_concat", "__kk_flow_flat_map_merge", "__kk_flow_flat_map_latest",
        ]
        let linkName = symbol.flatMap { ctx.sema?.symbols.externalLinkName(for: $0) }
        if name == "kk_flow_emit" || linkName == "kk_flow_emit" {
            guard arguments.count == 3 else { return nil }
            let tagExpr = arguments[2]
            let tag: Int64? = if case let .intLiteral(value)? = module.arena.expr(tagExpr) {
                value
            } else {
                constants[tagExpr]
            }
            guard let tag, tag != RuntimeFlowTag.emit.rawValue, RuntimeFlowTag(rawValue: tag) != nil else { return nil }
            return result
        }
        if factories.contains(name) || linkName.map(factories.contains) == true
            || (name == "flow" && !hasRealDeclaration(symbol, in: ctx))
            || symbol.map(freshFunctions.contains) == true {
            return result
        }
        return nil
    }

    private func flowIntegerConstants(_ body: [KIRInstruction]) -> [KIRExprID: Int64] {
        var constants: [KIRExprID: Int64] = [:]
        var mutable: Set<KIRExprID> = []
        for instruction in body {
            if case let .constValue(result, .intLiteral(value)) = instruction {
                if let previous = constants[result], previous != value { mutable.insert(result) }
                constants[result] = value
            } else {
                mutable.formUnion(definedExprIDs(in: instruction))
            }
        }
        for value in mutable { constants.removeValue(forKey: value) }
        return constants
    }

    // Only infer an owned return when every return is rooted in a fresh factory.
    // Identity operators and functions returning borrowed/global flows stay borrowed.
    func freshFlowFunctions(module: KIRModule, ctx: KIRContext) -> Set<SymbolID> {
        var fresh: Set<SymbolID> = []
        var changed = true
        while changed {
            changed = false
            for declaration in module.arena.declarations {
                guard case let .function(function) = declaration, !fresh.contains(function.symbol) else { continue }
                let constants = flowIntegerConstants(function.body)
                var values = Set(function.body.compactMap {
                    isFreshFlowCall($0, freshFunctions: fresh, constants: constants, module: module, ctx: ctx)
                })
                var propagated = true
                while propagated {
                    propagated = false
                    for instruction in function.body {
                        if case let .copy(from, to) = instruction, values.contains(from), values.insert(to).inserted {
                            propagated = true
                        }
                    }
                }
                let returns = function.body.compactMap { instruction -> KIRExprID? in
                    if case let .returnValue(value) = instruction { return value }
                    return nil
                }
                let hasOtherReturn = function.body.contains {
                    switch $0 {
                    case .returnUnit, .returnIfEqual, .nonLocalReturn: true
                    default: false
                    }
                }
                // An alias may have several reaching definitions; all must be fresh.
                let hasBorrowedWrite = function.body.contains { instruction in
                    switch instruction {
                    case let .copy(from, to): values.contains(to) && !values.contains(from)
                    case let .constValue(result, _), let .loadGlobal(result, _): values.contains(result)
                    case let .call(_, _, _, result, _, _, _, _):
                        result.map(values.contains) == true
                            && isFreshFlowCall(instruction, freshFunctions: fresh, constants: constants, module: module, ctx: ctx) == nil
                    default: false
                    }
                }
                let hasEscapingWrite = function.body.contains { instruction in
                    switch instruction {
                    case let .storeGlobal(value, _): values.contains(value)
                    case let .call(symbol, callee, arguments, _, _, _, _, _):
                        !values.isDisjoint(with: escapingFlowArguments(symbol, callee, arguments, ctx: ctx))
                    case let .virtualCall(symbol, callee, receiver, arguments, _, _, _, _):
                        !isFlowBorrowingCall(symbol, callee, ctx: ctx) && !values.isDisjoint(with: [receiver] + arguments)
                    default: false
                    }
                }
                if !returns.isEmpty, !hasOtherReturn, !hasBorrowedWrite, !hasEscapingWrite,
                   returns.allSatisfy(values.contains) {
                    fresh.insert(function.symbol)
                    changed = true
                }
            }
        }
        return fresh
    }

    private func isFlowBorrowingCall(_ symbol: SymbolID?, _ callee: InternedString, ctx: KIRContext) -> Bool {
        let name = ctx.interner.resolve(callee)
        let runtimeBorrowers: Set<String> = [
            "__kk_flow_retain", "__kk_flow_release", "kk_flow_collect", "__kk_flow_collectLatest",
            "__kk_flow_to_list", "__kk_flow_first", "__kk_flow_single", "kk_flow_emit",
            "__kk_flow_zip", "__kk_flow_combine", "__kk_flow_merge", "__kk_flow_flat_map_concat",
            "__kk_flow_flat_map_merge", "__kk_flow_flat_map_latest",
        ]
        if runtimeBorrowers.contains(name) { return true }
        let terminals: Set<String> = ["collect", "collectLatest", "toList", "first", "single", "collectCold"]
        guard terminals.contains(name) else { return false }
        if !hasRealDeclaration(symbol, in: ctx) { return true }
        guard let symbol, let info = ctx.sema?.symbols.symbol(symbol) else { return false }
        return info.fqName.prefix(3).map(ctx.interner.resolve) == ["kotlinx", "coroutines", "flow"]
    }

    private func escapingFlowArguments(
        _ symbol: SymbolID?, _ callee: InternedString, _ arguments: [KIRExprID], ctx: KIRContext
    ) -> Set<KIRExprID> {
        guard isFlowBorrowingCall(symbol, callee, ctx: ctx) else { return Set(arguments) }
        // Tagged emit borrows its source, but its payload can be emitted or saved as a fallback.
        if ctx.interner.resolve(callee) == "kk_flow_emit"
            || symbol.flatMap({ ctx.sema?.symbols.externalLinkName(for: $0) }) == "kk_flow_emit" {
            return Set(arguments.dropFirst())
        }
        return []
    }

    func cleanUpOwnedFlows(
        _ body: KIRLoweringEmitContext,
        module: KIRModule,
        ctx: KIRContext,
        freshFunctions: Set<SymbolID>
    ) -> KIRLoweringEmitContext {
        let constants = flowIntegerConstants(body.instructions)
        let roots = Set(body.instructions.compactMap {
            isFreshFlowCall($0, freshFunctions: freshFunctions, constants: constants, module: module, ctx: ctx)
        })
        guard !roots.isEmpty else { return body }
        var aliases = Dictionary(uniqueKeysWithValues: roots.map { ($0, Set([$0])) })
        var changed = true
        while changed {
            changed = false
            for instruction in body.instructions {
                guard case let .copy(from, to) = instruction else { continue }
                for root in roots where aliases[root]!.contains(from) || aliases[root]!.contains(to) {
                    if aliases[root]!.insert(from).inserted { changed = true }
                    if aliases[root]!.insert(to).inserted { changed = true }
                }
            }
        }
        let allAliases = aliases.values.reduce(into: Set<KIRExprID>()) { $0.formUnion($1) }
        let retain = ctx.interner.intern("__kk_flow_retain")
        let release = ctx.interner.intern("__kk_flow_release")
        // Calls that hand a suspend block to a coroutine which may run after
        // this scope ends — possibly on another thread (`produce`/`actor`/
        // `launch`/`async` and their runtime bridges). The block's captures
        // are marshalled by the launcher rewrite later, so nothing in this
        // body references a captured flow handle as a call argument yet;
        // without counting captures here a captured owned flow would be
        // released at its last lexical use while the launched block still
        // needs it.
        let asyncBoundaryCallees: Set<InternedString> = Set([
            "produce", "actor", "launch", "async",
            "__kk_produce_launch", "kk_produce", "kk_kxmini_produce_with_cont",
            "kk_coroutine_scope_launch", "kk_coroutine_scope_async",
            "channelFlow", "callbackFlow",
            "kk_channel_flow_create", "kk_callback_flow_create",
        ].map { ctx.interner.intern($0) })
        func capturedArguments(of expressions: [KIRExprID]) -> Set<KIRExprID> {
            var captured: Set<KIRExprID> = []
            var worklist = expressions
            while let expr = worklist.popLast() {
                let captures = module.arena.callableValueInfo(for: expr)?.captureArguments
                    ?? (module.arena.expr(expr).flatMap { exprValue -> SymbolID? in
                        guard case let .symbolRef(symbol) = exprValue else { return nil }
                        return symbol
                    }.flatMap { module.arena.lambdaCaptureArgsBySymbol[$0] })
                    ?? []
                for capture in captures where captured.insert(capture).inserted {
                    worklist.append(capture)
                }
            }
            return captured
        }
        var escaped: Set<KIRExprID> = []
        for instruction in body.instructions {
            var escaping: Set<KIRExprID>
            switch instruction {
            case .copy, .jump, .label, .jumpIfEqual, .jumpIfNotNull, .nop, .beginBlock, .endBlock,
                 .beginFinallyGuard, .endFinallyGuard:
                escaping = []
            case let .call(symbol, callee, arguments, _, _, _, _, _):
                escaping = escapingFlowArguments(symbol, callee, arguments, ctx: ctx)
                if asyncBoundaryCallees.contains(callee) {
                    escaping.formUnion(capturedArguments(of: arguments))
                }
            case let .virtualCall(symbol, callee, receiver, arguments, _, _, _, _):
                escaping = isFlowBorrowingCall(symbol, callee, ctx: ctx) ? [] : Set([receiver] + arguments)
                if asyncBoundaryCallees.contains(callee) {
                    escaping.formUnion(capturedArguments(of: [receiver] + arguments))
                }
            case let .storeGlobal(value, _), let .returnValue(value), let .rethrow(value): escaping = [value]
            case let .nonLocalReturn(value, _): escaping = Set(value.map { [$0] } ?? [])
            case let .unary(_, operand, _), let .nullAssert(operand, _): escaping = [operand]
            case let .binary(_, lhs, rhs, _), let .returnIfEqual(lhs, rhs): escaping = [lhs, rhs]
            default: escaping = []
            }
            escaped.formUnion(escaping.intersection(allAliases))
        }
        let instructions = body.instructions.enumerated().filter { _, instruction in
            // Replace lexical releases of original ownership, not balanced borrowed retains.
            if case let .call(_, callee, args, _, _, _, _, _) = instruction,
               callee == release, args.first.map(allAliases.contains) == true { return false }
            return true
        }
        let liveOut = computeLiveOutByInstruction(instructions.map(\.element))
        let outstandingAliases = Set(instructions.enumerated().compactMap { position, indexed -> KIRExprID? in
            guard let root = isFreshFlowCall(indexed.element, freshFunctions: freshFunctions, constants: constants, module: module, ctx: ctx),
                  let family = aliases[root],
                  !family.subtracting([root]).isDisjoint(with: liveOut[position] ?? []) else { return nil }
            return root
        })
        let ownedRoots = roots.filter {
            aliases[$0]!.isDisjoint(with: escaped) && !outstandingAliases.contains($0)
        }.sorted { $0.rawValue < $1.rawValue }
        guard !ownedRoots.isEmpty else {
            var result = KIRLoweringEmitContext()
            for (index, instruction) in instructions {
                result.currentSourceRange = body.instructionLocations[index]
                result.append(instruction)
            }
            return result
        }
        let null = module.arena.appendTemporary(type: ctx.sema?.types.nullableAnyType ?? .invalid)
        let slots = Dictionary(uniqueKeysWithValues: ownedRoots.map { root in
            let type = module.arena.exprType(root).flatMap { ctx.sema?.types.makeNullable($0) }
                ?? ctx.sema?.types.nullableAnyType ?? .invalid
            return (root, module.arena.appendTemporary(type: type))
        })
        var nextLabel = (body.instructions.compactMap { instruction -> Int32? in
            if case let .label(label) = instruction { return label }
            return nil
        }.max() ?? -1) + 1
        var result = KIRLoweringEmitContext()
        result.append(.constValue(result: null, value: .null))
        for root in ownedRoots { result.append(.copy(from: null, to: slots[root]!)) }
        let exceptionalExit = nextLabel
        nextLabel += 1
        var implicitThrown: KIRExprID?
        let nonThrowing = ABILoweringPass().nonThrowingCallees(interner: ctx.interner)
        func needsExplicitFailure(_ symbol: SymbolID?, _ callee: InternedString) -> Bool {
            let link = symbol.flatMap { ctx.sema?.symbols.externalLinkName(for: $0) }.map(ctx.interner.intern)
            return !nonThrowing.contains(link ?? callee) && !module.nonThrowingClosureCallees.contains(callee)
        }
        func explicitFailure(_ instruction: KIRInstruction) -> (KIRInstruction, KIRExprID?) {
            switch instruction {
            case let .call(symbol, callee, arguments, value, canThrow, nil, isSuper, qualifiedSuper)
                where needsExplicitFailure(symbol, callee):
                let thrown = implicitThrown ?? module.arena.appendTemporary(type: ctx.sema?.types.nullableAnyType ?? .invalid)
                implicitThrown = thrown
                return (.call(symbol: symbol, callee: callee, arguments: arguments, result: value,
                              canThrow: canThrow, thrownResult: thrown, isSuperCall: isSuper,
                              qualifiedSuperType: qualifiedSuper), thrown)
            case let .virtualCall(symbol, callee, receiver, arguments, value, canThrow, nil, dispatch)
                where needsExplicitFailure(symbol, callee):
                let thrown = implicitThrown ?? module.arena.appendTemporary(type: ctx.sema?.types.nullableAnyType ?? .invalid)
                implicitThrown = thrown
                return (.virtualCall(symbol: symbol, callee: callee, receiver: receiver, arguments: arguments,
                                     result: value, canThrow: canThrow, thrownResult: thrown, dispatch: dispatch), thrown)
            default: return (instruction, nil)
            }
        }
        func cleanUp(_ root: KIRExprID) {
            let skip = nextLabel
            nextLabel += 1
            let slot = slots[root]!
            result.append(.jumpIfEqual(lhs: slot, rhs: null, target: skip))
            result.append(.call(symbol: nil, callee: release, arguments: [slot], result: nil, canThrow: false, thrownResult: nil))
            result.append(.copy(from: null, to: slot))
            result.append(.label(skip))
        }
        var deferredFailure: KIRExprID?
        for (position, indexed) in instructions.enumerated() {
            let (index, instruction) = indexed
            result.currentSourceRange = body.instructionLocations[index]
            switch instruction {
            case .returnUnit, .returnValue, .rethrow, .nonLocalReturn:
                for root in ownedRoots { cleanUp(root) }
            case let .returnIfEqual(lhs, rhs):
                let returning = nextLabel
                let continuing = nextLabel + 1
                nextLabel += 2
                result.append(.jumpIfEqual(lhs: lhs, rhs: rhs, target: returning))
                result.append(.jump(continuing))
                result.append(.label(returning))
                for root in ownedRoots { cleanUp(root) }
                result.append(.returnValue(lhs))
                result.append(.label(continuing))
                continue
            default: break
            }
            let (emittedInstruction, failure) = explicitFailure(instruction)
            if let root = isFreshFlowCall(instruction, freshFunctions: freshFunctions, constants: constants, module: module, ctx: ctx), slots[root] != nil {
                // Handles created in a loop must not overwrite an outstanding owner.
                cleanUp(root)
                result.append(emittedInstruction)
                if let failure { result.append(.jumpIfNotNull(value: failure, target: exceptionalExit)) }
                if case let .call(_, _, _, _, _, thrown?, _, _) = emittedInstruction {
                    let failed = nextLabel
                    nextLabel += 1
                    result.append(.jumpIfNotNull(value: thrown, target: failed))
                    result.append(.copy(from: root, to: slots[root]!))
                    result.append(.label(failed))
                } else {
                    result.append(.copy(from: root, to: slots[root]!))
                }
            } else {
                result.append(emittedInstruction)
                if let deferred = deferredFailure {
                    result.append(.jumpIfNotNull(value: deferred, target: exceptionalExit))
                    deferredFailure = nil
                }
                if let failure {
                    // Balance a consume's borrowed retain before propagating its failure.
                    if position + 1 < instructions.count,
                       case .call(_, release, _, _, _, _, _, _) = instructions[position + 1].element {
                        deferredFailure = failure
                    } else {
                        result.append(.jumpIfNotNull(value: failure, target: exceptionalExit))
                    }
                }
            }
            switch instruction {
            case .call(_, retain, _, _, _, _, _, _), .jump, .jumpIfEqual, .jumpIfNotNull,
                 .label, .returnUnit, .returnValue, .rethrow, .returnIfEqual, .nonLocalReturn:
                continue
            default: break
            }
            for root in ownedRoots where aliases[root]!.isDisjoint(with: liveOut[position] ?? []) {
                if !usedExprIDs(in: instruction).isDisjoint(with: aliases[root]!) || definedExprIDs(in: instruction).contains(root) {
                    cleanUp(root)
                }
            }
        }
        for root in ownedRoots { cleanUp(root) }
        if let implicitThrown {
            let done = nextLabel
            nextLabel += 1
            result.append(.jump(done))
            result.append(.label(exceptionalExit))
            for root in ownedRoots { cleanUp(root) }
            result.append(.rethrow(value: implicitThrown))
            result.append(.label(done))
        }
        return result
    }
}
