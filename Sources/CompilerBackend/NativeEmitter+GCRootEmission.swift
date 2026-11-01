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

    // Retiring only shortens a handoff's lifetime, so skipping it for a
    // non-null primitive result is conservative: the word stays rooted until
    // the next safepoint or frame pop. Retiring it would instead cost a
    // GC-locked runtime call per arithmetic step in hot loops.
    func emitGCShadowRetireReturnHandoff(_ result: KIRExprID?, value: LLVMCAPIBindings.LLVMValueRef?) {
        guard let value, !bindings.isAggregateStructValue(value) else { return }
        if let result, result.rawValue >= 0, !isPotentialGCReference(module.arena.exprType(result)) {
            return
        }
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

    /// KUU-3778: the set-based iterative dataflow cost `O(iterations ×
    /// instructions × |live|)` with hashing and allocation — dominant on
    /// inline-expanded bodies (a 29k-instruction `main` spent ~85% of `emit`
    /// inside this one analysis). The same analysis is computed here as a
    /// basic-block fixpoint over dense bitsets plus a single backward
    /// expansion walk per block:
    ///   * gen/kill per block — O(instructions) sparse updates once;
    ///   * worklist fixpoint over blocks — O(visits × blocks × tracked/64)
    ///     word operations on ~an order of magnitude fewer points;
    ///   * one backward walk per block — each instruction pays only its own
    ///     sparse use/def bits, and the dead lists reduce to membership
    ///     checks (e.g. `deadAfter = (uses ∪ defs) − liveOut`).
    /// Outputs are identical: bit indices follow the ascending `rawValue`
    /// order the `sorted` calls produced.
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

        // Assign bit indices in ascending rawValue order so set-bit scans
        // yield the same sorted order the Set version's `sorted` produced.
        let trackedByRawValue = tracked.sorted { $0.rawValue < $1.rawValue }
        var bitIndexByRawValue: [Int32: Int] = [:]
        bitIndexByRawValue.reserveCapacity(trackedByRawValue.count)
        for (index, exprID) in trackedByRawValue.enumerated() {
            bitIndexByRawValue[exprID.rawValue] = index
        }
        let wordCount = (trackedByRawValue.count + 63) / 64

        var labelIndex: [Int32: Int] = [:]
        for (index, instruction) in body.enumerated() {
            if case let .label(id) = instruction, labelIndex[id] == nil {
                labelIndex[id] = index
            }
        }

        var useBits = Array(repeating: [Int](), count: count)
        var defBits = Array(repeating: [Int](), count: count)
        for (index, instruction) in body.enumerated() {
            defBits[index] = assignmentTargets(for: instruction)
                .compactMap { bitIndexByRawValue[$0.rawValue] }
            useBits[index] = useExpressions(for: instruction)
                .compactMap { bitIndexByRawValue[$0.rawValue] }
        }

        func instructionSuccessors(at index: Int) -> [Int] {
            switch body[index] {
            case let .jump(target):
                return labelIndex[target].map { [$0] } ?? []
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
                return branchSuccs
            case .returnIfEqual:
                return index + 1 < count ? [index + 1] : []
            case .returnUnit, .returnValue, .rethrow, .nonLocalReturn, .resumeNonLocalReturn:
                return []
            default:
                return index + 1 < count ? [index + 1] : []
            }
        }

        // Split the body into basic blocks. A block starts at a label, at the
        // first instruction, or right after a branch/terminator. The fixpoint
        // then iterates over blocks — O(blocks × tracked/64) word operations
        // per sweep instead of O(instructions × tracked/64) — and a single
        // backward walk per block expands the per-instruction results using
        // only sparse per-instruction updates.
        var blockOf = [Int](repeating: 0, count: count)
        var blockStart: [Int] = []
        blockStart.reserveCapacity(count / 8 + 1)
        for (index, instruction) in body.enumerated() {
            var leader = index == 0
            if !leader {
                switch instruction {
                case .label:
                    leader = true
                default:
                    switch body[index - 1] {
                    case .jump, .jumpIfEqual, .jumpIfNotNull, .returnIfEqual,
                         .beginNonLocalReturnScope, .returnUnit, .returnValue,
                         .rethrow, .nonLocalReturn, .resumeNonLocalReturn:
                        leader = true
                    default:
                        break
                    }
                }
            }
            if leader {
                blockStart.append(index)
            }
            blockOf[index] = blockStart.count - 1
        }
        let blockCount = blockStart.count
        var blockEnd = [Int](repeating: 0, count: blockCount)
        for block in 0 ..< blockCount {
            blockEnd[block] = (block + 1 < blockCount ? blockStart[block + 1] : count) - 1
        }

        // Block CFG: edges come from each block's last instruction only
        // (everything else inside a block is linear fallthrough).
        var blockSuccs = Array(repeating: [Int](), count: blockCount)
        var blockPreds = Array(repeating: [Int](), count: blockCount)
        for block in 0 ..< blockCount {
            var succBlocks: [Int] = []
            for succ in instructionSuccessors(at: blockEnd[block]) {
                let succBlock = blockOf[succ]
                if !succBlocks.contains(succBlock) {
                    succBlocks.append(succBlock)
                }
            }
            blockSuccs[block] = succBlocks
            for succBlock in succBlocks {
                blockPreds[succBlock].append(block)
            }
        }

        // Per-block gen/kill: gen = upward-exposed uses, kill = all defs.
        var gen = [UInt64](repeating: 0, count: blockCount * wordCount)
        var kill = [UInt64](repeating: 0, count: blockCount * wordCount)
        var seen = [UInt64](repeating: 0, count: wordCount)
        for block in 0 ..< blockCount {
            let base = block * wordCount
            for word in 0 ..< wordCount {
                seen[word] = 0
            }
            for index in blockStart[block] ... blockEnd[block] {
                for bit in useBits[index] {
                    let word = bit >> 6
                    let mask = UInt64(1) << UInt64(bit & 63)
                    if seen[word] & mask == 0 {
                        gen[base + word] |= mask
                    }
                }
                for bit in defBits[index] {
                    let word = bit >> 6
                    let mask = UInt64(1) << UInt64(bit & 63)
                    seen[word] |= mask
                    kill[base + word] |= mask
                }
            }
        }

        // Worklist fixpoint over blocks: liveOut[b] = ∪ liveIn[succ],
        // liveIn[b] = gen[b] ∪ (liveOut[b] − kill[b]). Same monotone
        // equations as the per-instruction version, so it converges to the
        // identical fixpoint at block boundaries.
        var liveIn = [UInt64](repeating: 0, count: blockCount * wordCount)
        var liveOut = [UInt64](repeating: 0, count: blockCount * wordCount)
        var worklist: [Int] = []
        worklist.reserveCapacity(blockCount)
        var inWorklist = [Bool](repeating: false, count: blockCount)
        // Seeded in forward order so popLast visits blocks back-to-front —
        // matching the information flow direction of a backward dataflow.
        for block in 0 ..< blockCount {
            worklist.append(block)
            inWorklist[block] = true
        }
        var newOut = [UInt64](repeating: 0, count: wordCount)
        var newIn = [UInt64](repeating: 0, count: wordCount)
        while let block = worklist.popLast() {
            inWorklist[block] = false
            let base = block * wordCount
            for word in 0 ..< wordCount {
                newOut[word] = 0
            }
            for succ in blockSuccs[block] {
                let succBase = succ * wordCount
                for word in 0 ..< wordCount {
                    newOut[word] |= liveIn[succBase + word]
                }
            }
            for word in 0 ..< wordCount {
                newIn[word] = gen[base + word] | (newOut[word] & ~kill[base + word])
            }
            var differs = false
            for word in 0 ..< wordCount {
                if newOut[word] != liveOut[base + word] || newIn[word] != liveIn[base + word] {
                    differs = true
                    break
                }
            }
            if differs {
                for word in 0 ..< wordCount {
                    liveOut[base + word] = newOut[word]
                    liveIn[base + word] = newIn[word]
                }
                for pred in blockPreds[block] where !inWorklist[pred] {
                    worklist.append(pred)
                    inWorklist[pred] = true
                }
            }
        }

        func bitIsSet(_ bits: [UInt64], _ bit: Int) -> Bool {
            bits[bit >> 6] & (UInt64(1) << UInt64(bit & 63)) != 0
        }

        /// Set-bit scan of `bits` in ascending rawValue order — identical to
        /// the old `subtracting(...).sorted` result.
        func emitSetBits(_ bits: [UInt64]) -> [KIRExprID] {
            var dead: [KIRExprID] = []
            for word in 0 ..< wordCount {
                var wordBits = bits[word]
                while wordBits != 0 {
                    let bit = wordBits.trailingZeroBitCount
                    dead.append(trackedByRawValue[word * 64 + bit])
                    wordBits &= wordBits - 1
                }
            }
            return dead
        }

        var deadAfterInstruction = Array(repeating: [KIRExprID](), count: count)
        var deadOnFallthrough = Array(repeating: [KIRExprID](), count: count)
        var deadOnLabelEntry = Array(repeating: [KIRExprID](), count: count)
        var current = [UInt64](repeating: 0, count: wordCount)
        var incoming = [UInt64](repeating: 0, count: wordCount)

        // One backward walk per block. `current` tracks the live-out bitset
        // of the instruction under the cursor; per-instruction updates only
        // touch the instruction's own sparse use/def bits. Algebraically the
        // dead lists reduce to sparse membership tests:
        //   deadAfter  = (uses ∪ defs) − liveOut[i]
        //   deadOnFallthrough = (uses ∪ defs ∪ liveOut[block]) − liveIn[next block]
        //   deadOnLabelEntry  = ∪p (uses[p] ∪ defs[p] ∪ liveOut[pred block]) − liveIn[block]
        for block in 0 ..< blockCount {
            let base = block * wordCount
            for word in 0 ..< wordCount {
                current[word] = liveOut[base + word]
            }
            var index = blockEnd[block]
            while index >= blockStart[block] {
                switch body[index] {
                case .constValue, .binary, .unary, .nullAssert, .call, .virtualCall,
                     .copy, .storeGlobal, .loadGlobal:
                    // dead = (uses ∪ defs) − liveOut[i]: sparse membership
                    // check, deduplicated and ascending like the old Set path.
                    var bits: [Int] = []
                    for bit in useBits[index] where !bitIsSet(current, bit) {
                        bits.append(bit)
                    }
                    for bit in defBits[index] where !bitIsSet(current, bit) {
                        bits.append(bit)
                    }
                    if !bits.isEmpty {
                        bits.sort()
                        var dead: [KIRExprID] = []
                        dead.reserveCapacity(bits.count)
                        var previous = -1
                        for bit in bits where bit != previous {
                            dead.append(trackedByRawValue[bit])
                            previous = bit
                        }
                        deadAfterInstruction[index] = dead
                    }
                case .jumpIfEqual, .jumpIfNotNull, .returnIfEqual:
                    // Branch instructions always end a block, so index + 1 is
                    // the next block's head (or out of bounds).
                    if index + 1 < count {
                        let nextBase = (block + 1) * wordCount
                        for word in 0 ..< wordCount {
                            incoming[word] = current[word] & ~liveIn[nextBase + word]
                        }
                        for bit in useBits[index] + defBits[index] {
                            let word = bit >> 6
                            let mask = UInt64(1) << UInt64(bit & 63)
                            if liveIn[nextBase + word] & mask == 0 {
                                incoming[word] |= mask
                            }
                        }
                        deadOnFallthrough[index] = emitSetBits(incoming)
                    }
                case .label:
                    var hasIncoming = false
                    for pred in blockPreds[block] {
                        let predBase = pred * wordCount
                        if hasIncoming {
                            for word in 0 ..< wordCount {
                                incoming[word] |= liveOut[predBase + word]
                            }
                        } else {
                            for word in 0 ..< wordCount {
                                incoming[word] = liveOut[predBase + word]
                            }
                            hasIncoming = true
                        }
                        let predEnd = blockEnd[pred]
                        for bit in useBits[predEnd] + defBits[predEnd] {
                            incoming[bit >> 6] |= UInt64(1) << UInt64(bit & 63)
                        }
                    }
                    if hasIncoming {
                        for word in 0 ..< wordCount {
                            incoming[word] &= ~liveIn[base + word]
                        }
                        deadOnLabelEntry[index] = emitSetBits(incoming)
                    }
                default:
                    break
                }
                // Propagate live values back: liveIn[i] = uses[i] ∪ (liveOut[i] − defs[i]).
                for bit in defBits[index] {
                    current[bit >> 6] &= ~(UInt64(1) << UInt64(bit & 63))
                }
                for bit in useBits[index] {
                    current[bit >> 6] |= UInt64(1) << UInt64(bit & 63)
                }
                index -= 1
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
