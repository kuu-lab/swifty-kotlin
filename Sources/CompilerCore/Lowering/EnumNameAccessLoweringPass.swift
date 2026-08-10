
/// Rewrites (valueOf result).name to $enumOrdinalToName(ordinal) and
/// (valueOf result).ordinal to kk_unbox_int(ordinal). Runs after
/// DataEnumSealedSynthesisPass which creates the $enumOrdinalToName helper.
///
/// Both `name` and `ordinal` are registered as synthetic .property symbols on
/// the shared kotlin.Enum<T> base class (registerEnumNameOrdinalProperties in
/// HeaderHelpers+SyntheticEnumStubs.swift), not as real per-class declarations.
/// Normal call-binding resolution never lands on a usable callee for them (see
/// the comment on the "name"/"ordinal" case in
/// CallLowerer+MemberCallEmission.swift's appendReceiverToMemberArguments), so
/// they always reach this pass as an unresolved `callee: "name"/"ordinal"`
/// call/virtualCall carrying the receiver as its sole argument, to be rewritten
/// here by pattern-matching the raw callee name.
final class EnumNameAccessLoweringPass: LoweringPass, ParallelLoweringPass {
    static let name = "EnumNameAccessLowering"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        module.ensureFeaturesScanned()
        let nameCallee = ctx.interner.intern("name")
        let ordinalCallee = ctx.interner.intern("ordinal")
        return module.usedCallees.contains(nameCallee)
            || module.usedCallees.contains(ordinalCallee)
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }
        let nameCallee = ctx.interner.intern("name")
        let ordinalCallee = ctx.interner.intern("ordinal")
        let stringType = sema.types.stringType
        let intType = sema.types.intType

        module.arena.transformFunctions { function in
            var newBody: [KIRInstruction] = []
            for instruction in function.body {
                let accessorAndReceiverAndResult: (InternedString, KIRExprID, KIRExprID?)? = switch instruction {
                case let .call(_, callee, arguments, result, _, _, _, _):
                    if callee == nameCallee || callee == ordinalCallee, arguments.count == 1 {
                        (callee, arguments[0], result)
                    } else {
                        nil
                    }
                case let .virtualCall(_, callee, receiver, _, result, _, _, _):
                    if callee == nameCallee || callee == ordinalCallee {
                        (callee, receiver, result)
                    } else {
                        nil
                    }
                default:
                    nil
                }
                guard let (accessorCallee, receiver, result) = accessorAndReceiverAndResult else {
                    newBody.append(instruction)
                    continue
                }
                let classSymbol: SymbolID? = {
                    if let argType = module.arena.exprType(receiver),
                       let (classType, sym) = resolveClassTypeSymbol(argType, sema: sema),
                       sym.kind == .enumClass
                    {
                        return classType.classSymbol
                    }
                    if case let .call(sym, _, args, _, _, _, _, _) = instruction,
                       let propSym = sym,
                       args.count == 1,
                       let propInfo = sema.symbols.symbol(propSym),
                       propInfo.kind == .property || propInfo.kind == .field,
                       propInfo.name == accessorCallee,
                       let parent = sema.symbols.parentSymbol(for: propSym),
                       let parentInfo = sema.symbols.symbol(parent),
                       parentInfo.kind == .enumClass
                    {
                        return parent
                    }
                    if case let .virtualCall(sym, _, _, _, _, _, _, _) = instruction,
                       let propSym = sym,
                       let propInfo = sema.symbols.symbol(propSym),
                       propInfo.kind == .property || propInfo.kind == .field,
                       propInfo.name == accessorCallee,
                       let parent = sema.symbols.parentSymbol(for: propSym),
                       let parentInfo = sema.symbols.symbol(parent),
                       parentInfo.kind == .enumClass
                    {
                        return parent
                    }
                    return nil
                }()
                guard let classSymbol else {
                    newBody.append(instruction)
                    continue
                }
                if accessorCallee == ordinalCallee {
                    // The KIR representation of an enum value already *is* its
                    // boxed ordinal (see $enumOrdinalToName's own first step
                    // below), so reading .ordinal is just unboxing it -- no
                    // per-class helper needed.
                    let targetResult = result ?? module.arena.appendTemporary(type: intType)
                    newBody.append(.call(
                        symbol: nil,
                        callee: ctx.interner.intern("kk_unbox_int"),
                        arguments: [receiver],
                        result: targetResult,
                        canThrow: false,
                        thrownResult: nil,
                        isSuperCall: false
                    ))
                    continue
                }
                if let classSym = sema.symbols.symbol(classSymbol) {
                    let helperName = ctx.interner.intern("$enumOrdinalToName$\(classSymbol.rawValue)")
                    let fqName = classSym.fqName + [helperName]
                    if let helperSymbol = sema.symbols.lookupAll(fqName: fqName).first(where: { id in
                        sema.symbols.symbol(id).map { $0.kind == .function } ?? false
                    }) {
                        let targetResult = result ?? module.arena.appendTemporary(type: stringType
                        )
                        newBody.append(.call(
                            symbol: helperSymbol,
                            callee: helperName,
                            arguments: [receiver],
                            result: targetResult,
                            canThrow: false,
                            thrownResult: nil,
                            isSuperCall: false
                        ))
                        continue
                    }
                }
                newBody.append(instruction)
            }
            var updated = function
            updated.replaceBody(newBody)
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func enumClassSymbol(
        for exprID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        instructions: [KIRInstruction]
    ) -> SymbolID? {
        // If the value was produced by an anonymous runtime call (symbol == nil),
        // such as kk_array_get, it may already contain a name string rather than a
        // raw ordinal — skip the $enumOrdinalToName transform to avoid double-conversion.
        for instruction in instructions.reversed() {
            switch instruction {
            case let .call(symbol, _, _, result, _, _, _, _) where result == exprID:
                if symbol == nil { return nil }
            case let .copy(_, to) where to == exprID:
                break
            default:
                continue
            }
            break
        }
        if let argType = arena.exprType(exprID),
           let (classType, sym) = resolveClassTypeSymbol(argType, sema: sema),
           sym.kind == .enumClass
        {
            return classType.classSymbol
        }
        return enumClassSymbolFromProducer(exprID: exprID, sema: sema, instructions: instructions)
    }

    private func enumClassSymbolFromProducer(
        exprID: KIRExprID,
        sema: SemaModule,
        instructions: [KIRInstruction]
    ) -> SymbolID? {
        for instruction in instructions.reversed() {
            switch instruction {
            case let .call(symbol, _, _, result, _, _, _, _):
                guard result == exprID else { continue }
                if let symbol {
                    return enumClassAncestor(of: symbol, sema: sema)
                }
                return nil
            case let .copy(from, to):
                if to == exprID {
                    return enumClassSymbolFromProducer(exprID: from, sema: sema, instructions: instructions)
                }
            default:
                break
            }
        }
        return nil
    }

    private func enumClassAncestor(of symbol: SymbolID, sema: SemaModule) -> SymbolID? {
        // A declared return type is authoritative: a function nested in an enum
        // (e.g. a companion member `EnumClass.f(): Int`) does not produce an
        // enum ordinal just because an enum class is one of its ancestors.
        if let signature = sema.symbols.functionSignature(for: symbol) {
            guard let (classType, returnSym) = resolveClassTypeSymbol(signature.returnType, sema: sema),
                  returnSym.kind == .enumClass
            else {
                return nil
            }
            return classType.classSymbol
        }
        var current: SymbolID? = symbol
        while let candidate = current {
            guard let info = sema.symbols.symbol(candidate) else { return nil }
            if info.kind == .enumClass {
                return candidate
            }
            current = sema.symbols.parentSymbol(for: candidate)
        }
        return nil
    }
}
