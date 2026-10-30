import CompilerCore

extension NativeEmitter.FunctionEmissionContext {
    func emitGCGlobalStore(
        symbol: SymbolID,
        pointer: LLVMCAPIBindings.LLVMValueRef,
        value: LLVMCAPIBindings.LLVMValueRef
    ) {
        let isThreadLocal = emitter.threadLocalGCGlobalSymbols.contains(symbol)
            || symbols?.annotations(for: symbol).contains(where: {
                KnownCompilerAnnotation.nativeThreadLocal.matches($0.annotationFQName)
            }) == true
        let calleeName = isThreadLocal ? "kk_gc_store_thread_local_global" : "kk_gc_store_global"
        guard let callee = declareExternalFunction(
            named: calleeName, argumentCount: 2, appendThrownChannel: false
        )
        else {
            _ = bindings.buildStore(builder, value: value, pointer: pointer)
            return
        }
        _ = bindings.buildCall(
            builder, functionType: callee.type, callee: callee.value,
            arguments: [pointer, value], name: "gc_global_store"
        )
    }

    // Shadow roots currently preserve scalar handles. Flat String aggregates,
    // native callbacks and safepoint publication still need explicit
    // treatment before retained runtime boxes can be swept.
    func emitGCShadowPush() {
        guard let callee = declareExternalFunction(
            named: "kk_gc_shadow_push", argumentCount: 0, appendThrownChannel: false
        ) else { return }
        _ = bindings.buildCall(builder, functionType: callee.type, callee: callee.value, arguments: [], name: "gc_frame_push")
        for (index, parameter) in function.params.enumerated() {
            guard isPotentialGCReference(parameter.type),
                  let value = bindings.getParam(function: llvmFunction.value, index: UInt32(index))
            else { continue }
            emitGCShadowSet(slot: index, value: value)
        }
    }

    func emitGCShadowSet(_ result: KIRExprID?, value: LLVMCAPIBindings.LLVMValueRef?) {
        guard let result, result.rawValue >= 0,
              isPotentialGCReference(module.arena.exprType(result))
        else { return }
        emitGCShadowSet(slot: function.params.count + Int(result.rawValue), value: value)
    }

    func gcShadowSlot(for result: KIRExprID) -> LLVMCAPIBindings.LLVMValueRef? {
        guard result.rawValue >= 0,
              isPotentialGCReference(module.arena.exprType(result)),
              !stringAggregateBridge.isStringAggregateType(module.arena.exprType(result))
        else { return nil }
        return bindings.constInt(int64Type, value: UInt64(function.params.count + Int(result.rawValue)))
    }

    private func emitGCShadowSet(slot: Int, value: LLVMCAPIBindings.LLVMValueRef?) {
        guard let value, !bindings.isAggregateStructValue(value),
              let index = bindings.constInt(int64Type, value: UInt64(bitPattern: Int64(slot)), signExtend: true),
              let callee = declareExternalFunction(
                  named: "kk_gc_shadow_set", argumentCount: 2, appendThrownChannel: false
              )
        else { return }
        _ = bindings.buildCall(builder, functionType: callee.type, callee: callee.value, arguments: [index, value], name: "gc_root_set")
    }

    func emitGCShadowRetireReturnHandoff(value: LLVMCAPIBindings.LLVMValueRef?) {
        guard let value, !bindings.isAggregateStructValue(value) else { return }
        emitGCShadowSet(slot: -1, value: value)
    }

    func prepareGCSafepoints() throws {
        guard let voidType = bindings.voidType(context: context),
              let enterFn = declareExternalFunction(
                  named: "__kk_gc_mutator_enter",
                  parameterTypes: [],
                  returnType: voidType
              ),
              let leaveFn = declareExternalFunction(
                  named: "__kk_gc_mutator_leave",
                  parameterTypes: [],
                  returnType: voidType
              ),
              let safepointFn = declareExternalFunction(
                  named: "__kk_gc_safepoint",
                  parameterTypes: [],
                  returnType: voidType
              )
        else {
            throw LLVMBackendError.nativeEmissionFailed("failed to declare GC safepoint hooks")
        }
        gcMutatorEnterFunction = enterFn
        gcMutatorLeaveFunction = leaveFn
        gcSafepointFunction = safepointFn
    }

    func emitGCMutatorEnter() {
        guard let enterFn = gcMutatorEnterFunction else { return }
        _ = bindings.buildCall(
            builder,
            functionType: enterFn.type,
            callee: enterFn.value,
            arguments: [],
            name: ""
        )
    }

    func emitGCMutatorLeave() {
        guard let leaveFn = gcMutatorLeaveFunction else { return }
        _ = bindings.buildCall(
            builder,
            functionType: leaveFn.type,
            callee: leaveFn.value,
            arguments: [],
            name: ""
        )
    }

    func emitGCSafepoint() {
        guard let safepointFn = gcSafepointFunction else { return }
        _ = bindings.buildCall(
            builder,
            functionType: safepointFn.type,
            callee: safepointFn.value,
            arguments: [],
            name: ""
        )
    }

    func emitGCShadowPop(result: LLVMCAPIBindings.LLVMValueRef? = nil, thrown: LLVMCAPIBindings.LLVMValueRef? = nil) {
        guard let callee = declareExternalFunction(
            named: "kk_gc_shadow_pop", argumentCount: 2, appendThrownChannel: false
        ) else { return }
        let returned = result.map { bindings.isAggregateStructValue($0) ? zeroValue! : $0 } ?? zeroValue!
        let exception = thrown.map { bindings.isAggregateStructValue($0) ? zeroValue! : $0 } ?? zeroValue!
        _ = bindings.buildCall(builder, functionType: callee.type, callee: callee.value, arguments: [returned, exception], name: "gc_frame_pop")
        emitGCMutatorLeave()
    }

    func clearDeadGCRoots(_ deadExpressions: [KIRExprID]) {
        guard !deadExpressions.isEmpty, !bindings.hasTerminator(currentBlock) else { return }
        for expr in deadExpressions {
            storeGCRoot(for: expr, value: zeroValue)
            emitGCShadowSet(expr, value: zeroValue)
        }
    }

    struct FunctionLivenessAnalysis {
        let deadAfterInstruction: [[KIRExprID]]
        let deadOnFallthrough: [[KIRExprID]]
        let deadOnLabelEntry: [[KIRExprID]]
    }

    func computeFunctionLivenessAnalysis() -> FunctionLivenessAnalysis {
        let body = function.body
        let count = body.count
        guard count > 0 else {
            return FunctionLivenessAnalysis(
                deadAfterInstruction: [],
                deadOnFallthrough: [],
                deadOnLabelEntry: []
            )
        }

        let tracked = Set(
            copyTargetAllocas.keys
                .map(KIRExprID.init(rawValue:))
                .filter { hasGCRootSlot(for: $0) }
        )
        guard !tracked.isEmpty else {
            return FunctionLivenessAnalysis(
                deadAfterInstruction: Array(repeating: [], count: count),
                deadOnFallthrough: Array(repeating: [], count: count),
                deadOnLabelEntry: Array(repeating: [], count: count)
            )
        }

        var labelIndex: [Int32: Int] = [:]
        for (index, instruction) in body.enumerated() {
            if case let .label(id) = instruction, labelIndex[id] == nil {
                labelIndex[id] = index
            }
        }

        var successors = Array(repeating: [Int](), count: count)
        var predecessors = Array(repeating: [Int](), count: count)
        var uses = Array(repeating: Set<KIRExprID>(), count: count)
        var defs = Array(repeating: Set<KIRExprID>(), count: count)

        for (index, instruction) in body.enumerated() {
            defs[index] = Set(assignmentTargets(for: instruction)).intersection(tracked)
            uses[index] = Set(useExpressions(for: instruction)).intersection(tracked)

            let succs: [Int]
            switch instruction {
            case let .jump(target):
                succs = labelIndex[target].map { [$0] } ?? []
            case let .jumpIfEqual(_, _, target),
                 let .jumpIfNotNull(_, target),
                 let .beginNonLocalReturnScope(_, target, _):
                var branchSuccs: [Int] = []
                if index + 1 < count {
                    branchSuccs.append(index + 1)
                }
                if let targetIdx = labelIndex[target], !branchSuccs.contains(targetIdx) {
                    branchSuccs.append(targetIdx)
                }
                succs = branchSuccs
            case .returnIfEqual:
                succs = index + 1 < count ? [index + 1] : []
            case .returnUnit, .returnValue, .rethrow, .nonLocalReturn, .resumeNonLocalReturn:
                succs = []
            default:
                succs = index + 1 < count ? [index + 1] : []
            }
            successors[index] = succs
            for succ in succs {
                predecessors[succ].append(index)
            }
        }

        var liveIn = Array(repeating: Set<KIRExprID>(), count: count)
        var liveOut = Array(repeating: Set<KIRExprID>(), count: count)
        var changed = true
        while changed {
            changed = false
            for index in stride(from: count - 1, through: 0, by: -1) {
                var newOut = Set<KIRExprID>()
                for succ in successors[index] {
                    newOut.formUnion(liveIn[succ])
                }
                let newIn = uses[index].union(newOut.subtracting(defs[index]))
                if newOut != liveOut[index] || newIn != liveIn[index] {
                    liveOut[index] = newOut
                    liveIn[index] = newIn
                    changed = true
                }
            }
        }

        var deadAfterInstruction = Array(repeating: [KIRExprID](), count: count)
        var deadOnFallthrough = Array(repeating: [KIRExprID](), count: count)
        var deadOnLabelEntry = Array(repeating: [KIRExprID](), count: count)

        for (index, instruction) in body.enumerated() {
            switch instruction {
            case .label:
                var incoming = Set<KIRExprID>()
                for pred in predecessors[index] {
                    incoming.formUnion(liveIn[pred])
                    incoming.formUnion(defs[pred])
                }
                let dead = incoming.subtracting(liveIn[index]).sorted { $0.rawValue < $1.rawValue }
                deadOnLabelEntry[index] = dead
            case .jumpIfEqual, .jumpIfNotNull, .returnIfEqual:
                if index + 1 < count {
                    let activeAtBranch = liveIn[index].union(defs[index])
                    let dead = activeAtBranch.subtracting(liveIn[index + 1]).sorted { $0.rawValue < $1.rawValue }
                    deadOnFallthrough[index] = dead
                }
            case .constValue, .binary, .unary, .nullAssert, .call, .virtualCall, .copy, .storeGlobal, .loadGlobal:
                let active = liveIn[index].union(defs[index])
                let dead = active.subtracting(liveOut[index]).sorted { $0.rawValue < $1.rawValue }
                deadAfterInstruction[index] = dead
            default:
                break
            }
        }

        return FunctionLivenessAnalysis(
            deadAfterInstruction: deadAfterInstruction,
            deadOnFallthrough: deadOnFallthrough,
            deadOnLabelEntry: deadOnLabelEntry
        )
    }

    private func useExpressions(for instruction: KIRInstruction) -> [KIRExprID] {
        switch instruction {
        case let .binary(_, lhs, rhs, _),
             let .jumpIfEqual(lhs, rhs, _),
             let .returnIfEqual(lhs, rhs):
            return [lhs, rhs]
        case let .unary(_, operand, _),
             let .nullAssert(operand, _),
             let .jumpIfNotNull(operand, _),
             let .copy(from: operand, _),
             let .storeGlobal(value: operand, _),
             let .rethrow(operand),
             let .returnValue(operand),
             let .resumeNonLocalReturn(operand),
             let .beginNonLocalReturnScope(value: operand, _, _):
            return [operand]
        case let .nonLocalReturn(value, _):
            return value.map { [$0] } ?? []
        case let .call(_, _, arguments, _, _, _, _, _):
            return arguments
        case let .virtualCall(_, _, receiver, arguments, _, _, _, _):
            return [receiver] + arguments
        case .nop, .beginBlock, .endBlock, .label, .jump, .constValue, .loadGlobal,
             .returnUnit, .endNonLocalReturnScope, .beginFinallyGuard, .endFinallyGuard,
             .beginFinallyCleanup, .endFinallyCleanup:
            return []
        }
    }

    private func isPotentialGCReference(_ type: TypeID?) -> Bool {
        guard let type, let typeSystem else { return true }
        switch typeSystem.kind(of: type) {
        case .primitive(_, .nonNull), .unit, .nullableUnit, .platformUnit, .nothing:
            return false
        default:
            return true
        }
    }
}
