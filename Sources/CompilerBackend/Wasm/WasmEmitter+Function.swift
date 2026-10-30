// WasmEmitter+Function.swift — per-function KIR → wasm body emission.
//
// KIR control flow is flat (label/jump/jumpIfEqual/jumpIfNotNull); wasm is
// structured. For each label we compute an enclosing interval — a forward
// jump target becomes a `block` ending at the label, a backward jump target
// becomes a `loop` starting at it — and then interleave block/loop opens and
// `end`s into the linear instruction stream. Non-laminar intervals (which
// the current lowerings never produce) are rejected with a diagnostic
// instead of miscompiled.

import Foundation
import CompilerCore

final class WasmFunctionEmission {
    let ctx: WasmModuleContext
    let function: KIRFunction
    var code = WasmCode()

    /// KIR expr id → wasm local. Only write-targets get a local; reads of
    /// unassigned ids are materialized from the expr kind directly.
    var localIndexByExpr: [Int32: Int] = [:]
    var paramLocalBySymbol: [Int32: Int] = [:]
    var scratchLocal = 0
    var nextLocal = 0

    struct LabelInterval {
        let label: Int32
        let open: Int
        let close: Int
        let isLoop: Bool
    }

    var intervals: [LabelInterval] = []
    var activeStack: [Int32] = [] // innermost last

    init(ctx: WasmModuleContext, function: KIRFunction) {
        self.ctx = ctx
        self.function = function
    }

    private var arena: KIRArena { ctx.kir.arena }

    func emitBody() throws -> [UInt8] {
        assignLocals()
        try computeIntervals()

        // Per-position open/close schedules.
        var opensAt: [Int: [LabelInterval]] = [:]
        var closesAt: [Int: [LabelInterval]] = [:]
        for interval in intervals {
            opensAt[interval.open, default: []].append(interval)
            closesAt[interval.close, default: []].append(interval)
        }
        for key in opensAt.keys {
            opensAt[key]?.sort { $0.close > $1.close } // outermost first
        }
        for key in closesAt.keys {
            closesAt[key]?.sort { $0.open > $1.open } // innermost first
        }

        for index in 0..<function.body.count {
            if let closing = closesAt[index] {
                for _ in closing {
                    _ = activeStack.popLast()
                    code.end()
                }
            }
            if let opening = opensAt[index] {
                for interval in opening {
                    if interval.isLoop {
                        code.openLoop()
                    } else {
                        code.openBlock()
                    }
                    activeStack.append(interval.label)
                }
            }
            try emitInstruction(function.body[index])
        }
        // The function's implicit frame end; any still-open intervals are a
        // compiler bug, but close them so the binary still validates.
        while !activeStack.isEmpty {
            activeStack.removeLast()
            code.end()
        }

        var body = WasmCode()
        let localCount = nextLocal - function.params.count
        if localCount > 0 {
            body.u(1) // one local declaration group
            body.u(UInt64(localCount))
            body.op(WasmValType.i64.rawValue)
        } else {
            body.u(0)
        }
        body.append(code)
        body.op(WasmOpcode.end)
        return body.bytes
    }

    // MARK: - Locals

    private func assignLocals() {
        nextLocal = function.params.count
        for (index, param) in function.params.enumerated() {
            paramLocalBySymbol[param.symbol.rawValue] = index
        }
        for instruction in function.body {
            switch instruction {
            case let .constValue(result, _),
                 let .binary(_, _, _, result),
                 let .unary(_, _, result),
                 let .nullAssert(_, result),
                 let .loadGlobal(result, _):
                assignLocal(result)
            case let .call(_, _, _, result, _, thrownResult, _, _):
                if let result { assignLocal(result) }
                if let thrownResult { assignLocal(thrownResult) }
            case let .virtualCall(_, _, _, _, result, _, thrownResult, _):
                if let result { assignLocal(result) }
                if let thrownResult { assignLocal(thrownResult) }
            case let .copy(_, to):
                assignLocal(to)
            default:
                break
            }
        }
        scratchLocal = nextLocal
        nextLocal += 8
    }

    private func assignLocal(_ id: KIRExprID) {
        if localIndexByExpr[id.rawValue] == nil {
            localIndexByExpr[id.rawValue] = nextLocal
            nextLocal += 1
        }
    }

    // MARK: - Structured control flow

    private func computeIntervals() throws {
        var labelPositions: [Int32: Int] = [:]
        var branches: [(pos: Int, target: Int32)] = []
        for (index, instruction) in function.body.enumerated() {
            switch instruction {
            case let .label(label):
                if labelPositions[label] == nil { labelPositions[label] = index }
            case let .jump(target):
                branches.append((index, target))
            case let .jumpIfEqual(_, _, target):
                branches.append((index, target))
            case let .jumpIfNotNull(_, target):
                branches.append((index, target))
            default:
                break
            }
        }
        for (label, position) in labelPositions {
            let targets = branches.filter { $0.target == label }
            guard !targets.isEmpty else { continue }
            let backward = targets.filter { $0.pos > position }
            let forward = targets.filter { $0.pos < position }
            if !backward.isEmpty, !forward.isEmpty {
                throw WasmEmitterError.nonLaminarControlFlow(
                    ctx.interner.resolve(function.name)
                )
            }
            if !backward.isEmpty {
                let close = backward.map(\.pos).max()! + 1
                intervals.append(LabelInterval(label: label, open: position, close: close, isLoop: true))
            } else {
                let open = forward.map(\.pos).min()!
                intervals.append(LabelInterval(label: label, open: open, close: position, isLoop: false))
            }
        }
        // Forward-jump intervals can cross (if/else: the join label's block
        // opens inside the else label's block but closes after it). Blocks are
        // transparent to fallthrough, so the later-closing interval can safely
        // open earlier and swallow the earlier one — the standard nesting fix.
        var changed = true
        while changed {
            changed = false
            for i in 0..<intervals.count {
                for j in 0..<intervals.count where i != j {
                    let a = intervals[i]
                    let b = intervals[j]
                    // Never move a loop's open: its header is the continue
                    // target. A forward block may still swallow a whole loop
                    // (a `br` to it from inside is then a break).
                    guard !b.isLoop else { continue }
                    if a.open < b.open, b.open < a.close, a.close < b.close {
                        intervals[j] = LabelInterval(
                            label: b.label, open: a.open, close: b.close, isLoop: false
                        )
                        changed = true
                    }
                }
            }
        }
        // Verify laminar nesting. Equal opens must order the longer (outer)
        // interval first so containment checks see it on the stack.
        let sorted = intervals.sorted {
            $0.open == $1.open ? $0.close > $1.close : $0.open < $1.open
        }
        var stack: [LabelInterval] = []
        for interval in sorted {
            while let top = stack.last, top.close <= interval.open {
                stack.removeLast()
            }
            if let top = stack.last, interval.close > top.close {
                throw WasmEmitterError.nonLaminarControlFlow(
                    ctx.interner.resolve(function.name)
                )
            }
            stack.append(interval)
        }
    }

    private func branchDepth(to label: Int32) throws -> Int {
        guard let position = activeStack.lastIndex(of: label) else {
            throw WasmEmitterError.nonLaminarControlFlow(
                ctx.interner.resolve(function.name)
            )
        }
        return activeStack.count - 1 - position
    }

    // MARK: - Value resolution

    /// Pushes the i64 value of `id` onto the operand stack.
    func resolveValue(_ id: KIRExprID) {
        if let local = localIndexByExpr[id.rawValue] {
            code.localGet(local)
            return
        }
        emitExprValue(arena.expr(id), for: id)
    }

    /// Emits code that pushes the value described by `expr` (materializing
    /// literals, symbol references, and string objects inline).
    private func emitExprValue(_ expr: KIRExprKind?, for id: KIRExprID) {
        switch expr {
        case let .intLiteral(value), let .longLiteral(value):
            code.i64Const(value)
        case let .uintLiteral(value), let .ulongLiteral(value):
            code.i64Const(Int64(bitPattern: value))
        case let .floatLiteral(value):
            code.i64Const(Int64(Float(value).bitPattern))
        case let .doubleLiteral(value):
            code.i64Const(Int64(bitPattern: value.bitPattern))
        case let .charLiteral(value):
            code.i64Const(Int64(value))
        case let .boolLiteral(value):
            code.i64Const(value ? 1 : 0)
        case let .stringLiteral(literal):
            emitStringLiteral(literal)
        case let .symbolRef(symbol):
            emitSymbolRef(symbol)
        case let .externSymbolAddress(name):
            emitExternSymbolAddress(name)
        case let .temporary(raw):
            code.i64Const(Int64(raw))
        case .null:
            code.i64Const(nullRepresentation(for: id))
        case .unit, nil:
            code.i64Const(0)
        }
    }

    /// `.null` uses 0 for reference types and the Int64.min sentinel for
    /// erased/raw contexts, matching the native dual representation.
    private func nullRepresentation(for id: KIRExprID) -> Int64 {
        if let type = arena.exprType(id),
           let types = ctx.types,
           case .classType = types.kind(of: type)
        {
            return 0
        }
        return WasmModuleContext.WasmLayout.nullSentinel
    }

    private func emitSymbolRef(_ symbol: SymbolID) {
        if let param = paramLocalBySymbol[symbol.rawValue] {
            code.localGet(param)
            return
        }
        if let global = ctx.globalIndexBySymbol[symbol] {
            code.globalGet(global)
            return
        }
        if let functionIndex = ctx.functionIndexBySymbol[symbol] {
            let slot = ctx.module.tableSlot(forFunction: functionIndex)
            code.i64Const(Int64(slot))
            return
        }
        // Library member implementations reach vtable/itable registrations
        // as symbolRefs without a materialized function — map known stdlib
        // members onto their wasm helpers so the slot stays callable.
        if let thunk = ctx.memberThunkInfo(for: symbol) {
            let helperIndex = ctx.emittedHelperIndex(
                for: thunk.helper, argumentCount: thunk.arity
            )
            code.i64Const(Int64(ctx.module.tableSlot(forFunction: helperIndex)))
            return
        }
        // Nominal types and other symbols carry a stable identity value.
        code.i64Const(Int64(max(1, symbol.rawValue)))
    }

    private func emitExternSymbolAddress(_ name: InternedString) {
        let resolved = ctx.interner.resolve(name)
        for (symbol, functionIndex) in ctx.functionIndexBySymbol {
            if ctx.symbols?.externalLinkName(for: symbol) == resolved {
                if ProcessInfo.processInfo.environment["KSWIFTK_WASM_EXTERN_TRACE"] != nil {
                    FileHandle.standardError.write(
                        "extern '\(resolved)' -> symbol \(symbol.rawValue) slot \(ctx.module.tableSlot(forFunction: functionIndex))\n".data(using: .utf8)!)
                }
                code.i64Const(Int64(ctx.module.tableSlot(forFunction: functionIndex)))
                return
            }
        }
        // Synthesized module functions (`kk_closure_thunk_adapter_*` etc.)
        // register under their decl name rather than the `kk_fn_` link name —
        // demangle (and un-escape `_`→`__`) to find them in the name/arity
        // table. Only a unique match is safe to call.
        if resolved.hasPrefix("kk_fn_"),
           let inner = WasmModuleContext.demangleKkFnName(resolved) {
            var candidates = [inner]
            if !inner.hasPrefix("__"), inner.contains("__") {
                candidates.append(inner.replacingOccurrences(of: "__", with: "_"))
            }
            var match: Int?
            var ambiguous = false
            for candidate in candidates {
                for (key, index) in ctx.functionIndexByNameArity
                where key.hasPrefix("\(candidate)/") {
                    if let existing = match, existing != index { ambiguous = true }
                    match = index
                }
            }
            if let match, !ambiguous {
                if ProcessInfo.processInfo.environment["KSWIFTK_WASM_EXTERN_TRACE"] != nil {
                    FileHandle.standardError.write(
                        "extern '\(resolved)' -> decl \(match) slot \(ctx.module.tableSlot(forFunction: match))\n".data(using: .utf8)!)
                }
                code.i64Const(Int64(ctx.module.tableSlot(forFunction: match)))
                return
            }
        }
        // The member's body wasn't materialized — demangle `kk_fn_<name>_*`
        // link names and fall back to an emitted helper so the registered
        // table slot dispatches instead of silently staying 0. Itable
        // registrations always take the receiver as arg0, matching each
        // helper's signature.
        if resolved.hasPrefix("kk_fn_"),
           let helper = ctx.externLinkNameHelper(forLinkName: resolved)
        {
            let helperIndex = ctx.emittedHelperIndex(
                for: helper.name, argumentCount: helper.arity
            )
            if ProcessInfo.processInfo.environment["KSWIFTK_WASM_EXTERN_TRACE"] != nil {
                FileHandle.standardError.write(
                    "extern '\(resolved)' -> helper '\(helper.name)' slot \(ctx.module.tableSlot(forFunction: helperIndex))\n".data(using: .utf8)!)
            }
            code.i64Const(Int64(ctx.module.tableSlot(forFunction: helperIndex)))
            return
        }
        if ProcessInfo.processInfo.environment["KSWIFTK_WASM_EXTERN_TRACE"] != nil {
            FileHandle.standardError.write(
                "extern '\(resolved)' -> 0 (unresolved)\n".data(using: .utf8)!)
        }
        code.i64Const(0)
    }

    /// Materializes a flat String object {data, length, byteCount, hash} whose
    /// UTF-8 bytes live in an active data segment.
    private func emitStringLiteral(_ literal: InternedString) {
        let offset = stringOffset(for: literal)
        let string = ctx.interner.resolve(literal)
        code.i64Const(offset)
        code.i64Const(Int64(Array(string.utf8).count))
        code.call(ctx.emittedHelperIndex(for: "__kk_string_literal_from_utf8", argumentCount: 2))
    }

    private func stringOffset(for literal: InternedString) -> Int64 {
        if let existing = ctx.stringOffsetByLiteral[literal] { return existing }
        let string = ctx.interner.resolve(literal)
        let bytes = Array(string.utf8)
        let offset = ctx.dataCursor
        ctx.dataCursor += Int64(bytes.count)
        ctx.stringOffsetByLiteral[literal] = offset
        ctx.module.addDataSegment(offset: offset, bytes: bytes)
        return offset
    }

    // MARK: - Thrown channel

    private func emitThrownCheck(thrownResult: KIRExprID?) {
        if let thrownResult, let local = localIndexByExpr[thrownResult.rawValue] {
            // Consume the channel into the slot and continue: the lowered
            // jumpIfNotNull routes to the catch handler or a rethrow.
            code.globalGet(ctx.thrownGlobal)
            code.localSet(local)
            code.i64Const(0)
            code.globalSet(ctx.thrownGlobal)
            return
        }
        // No local handler — propagate the thrown value to the caller.
        code.globalGet(ctx.thrownGlobal)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.elseBranch()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
    }

    private func emitCallResult(result: KIRExprID?, canThrow: Bool, thrownResult: KIRExprID?) {
        if let result, let local = localIndexByExpr[result.rawValue] {
            code.localSet(local)
        } else {
            code.op(WasmOpcode.drop)
        }
        if canThrow {
            emitThrownCheck(thrownResult: thrownResult)
        } else if let thrownResult, let local = localIndexByExpr[thrownResult.rawValue] {
            code.i64Const(0)
            code.localSet(local)
        }
    }

    // MARK: - Instructions

    private func emitInstruction(_ instruction: KIRInstruction) throws {
        switch instruction {
        case .nop, .beginBlock, .endBlock,
             .beginFinallyGuard, .endFinallyGuard,
             .beginFinallyCleanup, .endFinallyCleanup,
             .beginNonLocalReturnScope, .endNonLocalReturnScope:
            break

        case .label:
            break // positions only; structure handled by intervals

        case let .constValue(result, value):
            if let local = localIndexByExpr[result.rawValue] {
                emitExprValue(value, for: result)
                code.localSet(local)
            }

        case let .binary(op, lhs, rhs, result):
            resolveValue(lhs)
            resolveValue(rhs)
            emitBinaryOp(op)
            if let local = localIndexByExpr[result.rawValue] {
                code.localSet(local)
            } else {
                code.op(WasmOpcode.drop)
            }

        case let .unary(op, operand, result):
            resolveValue(operand)
            emitUnaryOp(op)
            if let local = localIndexByExpr[result.rawValue] {
                code.localSet(local)
            } else {
                code.op(WasmOpcode.drop)
            }

        case let .nullAssert(operand, result):
            // v1: pass-through. A null-check trap belongs to M2 NPE work.
            resolveValue(operand)
            if let local = localIndexByExpr[result.rawValue] {
                code.localSet(local)
            } else {
                code.op(WasmOpcode.drop)
            }

        case let .call(symbol, callee, arguments, result, canThrow, thrownResult, _, _):
            emitCall(
                symbol: symbol,
                callee: callee,
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult
            )

        case let .virtualCall(_, _, receiver, arguments, result, canThrow, thrownResult, dispatch):
            emitVirtualCall(
                receiver: receiver,
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult,
                dispatch: dispatch
            )

        case let .copy(from, to):
            resolveValue(from)
            if let local = localIndexByExpr[to.rawValue] {
                code.localSet(local)
            } else {
                code.op(WasmOpcode.drop)
            }

        case let .storeGlobal(value, symbol):
            resolveValue(value)
            code.globalSet(globalIndex(for: symbol))

        case let .loadGlobal(result, symbol):
            code.globalGet(globalIndex(for: symbol))
            if let local = localIndexByExpr[result.rawValue] {
                code.localSet(local)
            } else {
                code.op(WasmOpcode.drop)
            }

        case let .rethrow(value):
            resolveValue(value)
            code.localTee(scratchLocal)
            code.op(WasmOpcode.i64Eqz)
            code.openIf()
            // A 0 thrown value means the exception object came from a stubbed
            // constructor; substitute a marker so the throw isn't swallowed.
            code.i64Const(1)
            code.globalSet(ctx.thrownGlobal)
            code.elseBranch()
            code.localGet(scratchLocal)
            code.globalSet(ctx.thrownGlobal)
            code.end()
            code.i64Const(0)
            code.op(WasmOpcode.return)

        case let .returnIfEqual(lhs, rhs):
            resolveValue(lhs)
            resolveValue(rhs)
            code.op(WasmOpcode.i64Eq)
            code.openIf()
            code.i64Const(0)
            code.op(WasmOpcode.return)
            code.end()

        case .returnUnit:
            code.i64Const(0)
            code.op(WasmOpcode.return)

        case let .returnValue(value):
            resolveValue(value)
            code.op(WasmOpcode.return)

        case let .nonLocalReturn(value, target):
            if case let .function(targetSymbol) = target, targetSymbol != function.symbol {
                ctx.notes.append(
                    "nonLocalReturn crossing function boundary in '\(ctx.interner.resolve(function.name))' is approximated as a local return"
                )
            }
            if let value {
                resolveValue(value)
            } else {
                code.i64Const(0)
            }
            code.op(WasmOpcode.return)

        case let .resumeNonLocalReturn(value):
            ctx.notes.append(
                "resumeNonLocalReturn in '\(ctx.interner.resolve(function.name))' approximated as local return; finally-based NLR is not yet supported on wasm"
            )
            resolveValue(value)
            code.op(WasmOpcode.return)

        case let .jump(target):
            code.br(try branchDepth(to: target))

        case let .jumpIfEqual(lhs, rhs, target):
            resolveValue(lhs)
            resolveValue(rhs)
            code.op(WasmOpcode.i64Eq)
            code.brIf(try branchDepth(to: target))

        case let .jumpIfNotNull(value, target):
            // Null covers both the zero reference and the Int64.min sentinel.
            resolveValue(value)
            code.i64Const(0)
            code.op(WasmOpcode.i64Ne)
            resolveValue(value)
            code.i64Const(WasmModuleContext.WasmLayout.nullSentinel)
            code.op(WasmOpcode.i64Ne)
            code.op(WasmOpcode.i32And)
            code.brIf(try branchDepth(to: target))
        }
    }

    private func globalIndex(for symbol: SymbolID) -> Int {
        if let existing = ctx.globalIndexBySymbol[symbol] { return existing }
        let index = ctx.module.addGlobal(initialValue: 0, name: "$g\(symbol.rawValue)")
        ctx.globalIndexBySymbol[symbol] = index
        return index
    }

    private func emitBinaryOp(_ op: KIRBinaryOp) {
        switch op {
        case .add: code.op(WasmOpcode.i64Add)
        case .subtract: code.op(WasmOpcode.i64Sub)
        case .multiply: code.op(WasmOpcode.i64Mul)
        case .divide: code.op(WasmOpcode.i64DivS)
        case .modulo: code.op(WasmOpcode.i64RemS)
        case .equal: code.op(WasmOpcode.i64Eq); code.i64ExtendFromComparison()
        case .notEqual: code.op(WasmOpcode.i64Ne); code.i64ExtendFromComparison()
        case .lessThan: code.op(WasmOpcode.i64LtS); code.i64ExtendFromComparison()
        case .lessOrEqual: code.op(WasmOpcode.i64LeS); code.i64ExtendFromComparison()
        case .greaterThan: code.op(WasmOpcode.i64GtS); code.i64ExtendFromComparison()
        case .greaterOrEqual: code.op(WasmOpcode.i64GeS); code.i64ExtendFromComparison()
        case .logicalAnd: code.op(WasmOpcode.i64And)
        case .logicalOr: code.op(WasmOpcode.i64Or)
        }
    }

    private func emitUnaryOp(_ op: KIRUnaryOp) {
        switch op {
        case .not:
            code.op(WasmOpcode.i64Eqz)
            code.i64ExtendFromComparison()
        case .unaryPlus:
            break
        case .unaryMinus:
            // 0 - operand: rebuild as a sub since wasm has no negate.
            // The operand was already pushed; re-push 0 below it is not
            // possible, so swap via a scratch local.
            code.localSet(scratchLocal)
            code.i64Const(0)
            code.localGet(scratchLocal)
            code.op(WasmOpcode.i64Sub)
        }
    }

    // MARK: - Calls

    private func emitCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?
    ) {
        let name = ctx.interner.resolve(callee)

        // Inline builtins consume pushed args directly.
        if WasmRuntimeHelpers.isInlineCallee(name) {
            for argument in arguments { resolveValue(argument) }
            WasmRuntimeHelpers.emitInlineCallee(
                name: name,
                code: &code,
                ctx: ctx,
                emission: self
            )
            emitCallResult(result: result, canThrow: canThrow, thrownResult: thrownResult)
            return
        }

        let resolution = ctx.resolveCallee(
            name: name,
            symbol: symbol,
            argumentCount: arguments.count,
            argumentTypes: arguments.map { arena.exprType($0) }
        )
        for argument in arguments { resolveValue(argument) }
        switch resolution {
        case let .direct(index):
            code.call(index)
        case let .emittedHelper(index):
            code.call(index)
        case let .stub(stubName):
            code.call(ctx.stubIndex(for: stubName, argumentCount: arguments.count))
        }
        emitCallResult(result: result, canThrow: canThrow, thrownResult: thrownResult)
    }

    private func emitVirtualCall(
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        dispatch: KIRDispatchKind
    ) {
        // Push receiver + args first; then compute the funcref index.
        resolveValue(receiver)
        for argument in arguments { resolveValue(argument) }

        switch dispatch {
        case let .vtable(slot):
            emitVtableIndex(receiver: receiver, slot: slot)
        case let .itable(interfaceSlot, methodSlot):
            emitItableIndex(
                receiver: receiver,
                interfaceSlot: interfaceSlot,
                methodSlot: methodSlot
            )
        case let .itableDynamic(interfaceTypeID, methodSlot):
            // `Lazy.isInitialized` / `Lazy.value` — the member bodies live in
            // the kklib and are not materializable into this module, so the
            // caller-side itable entries resolve to dead extern slots. Route
            // the interface dispatch straight to the emitted lazy helpers;
            // they implement the same field protocol on the LazyImpl layout.
            if interfaceTypeID == WasmRuntimeHelpers.stableNominalTypeID("kotlin.Lazy"),
               arguments.isEmpty, methodSlot <= 1 {
                let helper = methodSlot == 0
                    ? "kk_lazy_is_initialized" : "kk_lazy_get_value"
                code.call(ctx.emittedHelperIndex(for: helper, argumentCount: 1))
                emitCallResult(result: result, canThrow: canThrow, thrownResult: thrownResult)
                return
            }
            // Resolve the interface slot from the object's iface map. A
            // lookup miss yields table index 0 — trap rather than call
            // whatever funcref happens to live there (native's
            // kk_dispatch_error equivalent).
            resolveValue(receiver)
            code.i64Const(interfaceTypeID)
            code.i64Const(Int64(methodSlot))
            code.call(ctx.emittedHelperIndex(for: "__kk_wasm_itable_lookup", argumentCount: 3))
            code.localTee(scratchLocal)
            code.op(WasmOpcode.i64Eqz)
            code.openIf()
            code.op(WasmOpcode.unreachable)
            code.end()
            code.localGet(scratchLocal)
            code.op(WasmOpcode.i32WrapI64)
        }

        let arity = 1 + arguments.count
        let typeIndex = ctx.module.funcTypeIndex(.i64Signature(arity))
        code.callIndirect(typeIndex)
        emitCallResult(result: result, canThrow: canThrow, thrownResult: thrownResult)
    }

    /// Pushes `vtable[slot]` of the receiver as a funcref-table index (i32).
    /// The vtable pointer lives in body slot 1 (base+8); a null vtable or an
    /// empty slot traps instead of silently calling a wrong table entry.
    private func emitVtableIndex(receiver: KIRExprID, slot: Int) {
        resolveValue(receiver)
        code.op(WasmOpcode.i32WrapI64)
        code.i64Load(offset: UInt64(WasmModuleContext.WasmLayout.vtableSlotOffset))
        code.localTee(scratchLocal)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.op(WasmOpcode.unreachable)
        code.end()
        code.localGet(scratchLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.i64Load(offset: UInt64(slot * 8))
        code.localTee(scratchLocal)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.op(WasmOpcode.unreachable)
        code.end()
        code.localGet(scratchLocal)
        code.op(WasmOpcode.i32WrapI64)
    }

    /// Pushes `itable[interfaceSlot*stride + methodSlot]` of the receiver as a
    /// funcref-table index (i32). The itable buffer pointer lives in the
    /// vtable header at `vtableItablePtrOffset`; a null vtable, missing itable
    /// buffer, or empty slot traps rather than misdispatching.
    private func emitItableIndex(receiver: KIRExprID, interfaceSlot: Int, methodSlot: Int) {
        resolveValue(receiver)
        code.op(WasmOpcode.i32WrapI64)
        code.i64Load(offset: UInt64(WasmModuleContext.WasmLayout.vtableSlotOffset))
        code.localTee(scratchLocal)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.op(WasmOpcode.unreachable)
        code.end()
        code.localGet(scratchLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(Int32(WasmModuleContext.WasmLayout.vtableItablePtrOffset))
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.localTee(scratchLocal)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.op(WasmOpcode.unreachable)
        code.end()
        code.localGet(scratchLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.i64Load(
            offset: UInt64(
                (interfaceSlot * WasmModuleContext.WasmLayout.itableStride + methodSlot) * 8
            )
        )
        code.localTee(scratchLocal)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.op(WasmOpcode.unreachable)
        code.end()
        code.localGet(scratchLocal)
        code.op(WasmOpcode.i32WrapI64)
    }
}

