
/// Rewrites (valueOf result).name to $enumOrdinalToName(ordinal) and
/// (valueOf result).ordinal to kk_unbox_int(ordinal). Runs after
/// DataEnumSealedSynthesisPass which creates the $enumOrdinalToName helper.
///
/// `name` and `ordinal` are source-backed properties on the shared kotlin.Enum
/// base class. Their representation is still compiler-owned, so this pass
/// rewrites the source member access to the per-enum residual helpers. The
/// synthetic registration in HeaderHelpers+SyntheticEnumStubs.swift remains a
/// fallback for source-less enum surfaces.
final class EnumNameAccessLoweringPass: LoweringPass, ParallelLoweringPass {
    static let name = "EnumNameAccessLowering"
    static let requiredStage: KIRStage = .propertyLowered
    static let producedStage: KIRStage = .propertyLowered

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        module.ensureFeaturesScanned()
        let nameCallee = ctx.interner.intern("name")
        let ordinalCallee = ctx.interner.intern("ordinal")
        let kkAnyMemberToStringCallee = ctx.interner.intern("kk_any_member_to_string")
        let enumConstructorPropertyPrefix = "$enumConstructorProperty$"
        return module.usedCallees.contains(nameCallee)
            || module.usedCallees.contains(ordinalCallee)
            || module.usedCallees.contains(kkAnyMemberToStringCallee)
            || module.usedCallees.contains(where: { ctx.interner.resolve($0).hasPrefix(enumConstructorPropertyPrefix) })
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }
        let nameCallee = ctx.interner.intern("name")
        let ordinalCallee = ctx.interner.intern("ordinal")
        let kkAnyMemberToStringCallee = ctx.interner.intern("kk_any_member_to_string")
        let stringType = sema.types.stringType
        let intType = sema.types.intType

        module.arena.transformFunctions { function in
            var newBody = KIRLoweringEmitContext()
            for (index, instruction) in function.body.enumerated() {
                newBody.currentSourceRange = index < function.instructionLocations.count
                    ? function.instructionLocations[index]
                    : nil
                if let rewritten = rewriteEnumStringConversionCall(
                    instruction: instruction,
                    sema: sema,
                    arena: module.arena,
                    interner: ctx.interner,
                    precedingInstructions: newBody.instructions,
                    kkAnyMemberToStringCallee: kkAnyMemberToStringCallee
                ) {
                    newBody.append(contentsOf: rewritten)
                    continue
                }
                if let rewritten = rewriteEnumConstructorPropertyCall(
                    instruction: instruction,
                    sema: sema,
                    arena: module.arena,
                    interner: ctx.interner
                ) {
                    newBody.append(contentsOf: rewritten)
                    continue
                }
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
                    let helperName = NameMangler.enumOrdinalToNameHelperName(for: classSym, interner: ctx.interner)
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

    /// `enumValue.toString()` binds to `kotlin.Any.toString` and, absent a
    /// user override, renders the bare entry name via `$enumOrdinalToName`.
    /// BUG-A/BUG-Planet: prefer an actual `toString()` implementation when
    /// the enum class declares one -- either directly on the class body
    /// (`enumToStringOverrideHelper`'s class-level branch) or through the
    /// per-entry dispatch helper reached when only some entry bodies
    /// override `toString()` (`Op.MUL`'s case, after `EnumEntryBodyHeaders`
    /// registers it as a dispatch target).
    private func rewriteEnumStringConversionCall(
        instruction: KIRInstruction,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        precedingInstructions: [KIRInstruction],
        kkAnyMemberToStringCallee: InternedString
    ) -> [KIRInstruction]? {
        guard case let .call(_, callee, arguments, result, _, _, _, _) = instruction,
              callee == kkAnyMemberToStringCallee,
              arguments.count == 1,
              let classSymbol = enumClassSymbol(
                  for: arguments[0],
                  sema: sema,
                  arena: arena,
                  instructions: precedingInstructions
              ),
              let classSym = sema.symbols.symbol(classSymbol)
        else {
            return nil
        }

        let helperName: InternedString
        let helperSymbol: SymbolID?
        if let override = enumToStringOverrideHelper(for: classSym, symbols: sema.symbols, interner: interner) {
            helperName = override.name
            helperSymbol = override.symbol
        } else {
            let fallbackName = NameMangler.enumOrdinalToNameHelperName(for: classSym, interner: interner)
            guard let fallbackSymbol = sema.symbols.lookupAll(fqName: classSym.fqName + [fallbackName]).first(where: { id in
                sema.symbols.symbol(id).map { $0.kind == .function } ?? false
            }) else {
                return nil
            }
            helperName = fallbackName
            helperSymbol = fallbackSymbol
        }

        return [.call(
            symbol: helperSymbol,
            callee: helperName,
            arguments: [arguments[0]],
            result: result,
            canThrow: false,
            thrownResult: nil,
            isSuperCall: false
        )]
    }

    /// Rewrites a placeholder call emitted by `tryLowerStoredMemberPropertyRead`
    /// for an enum class constructor property (`enum class Status(val code: Int)`)
    /// into a real call to the per-enum, per-property `$enumConstructorProperty$`
    /// helper synthesized by `KIRLoweringDriver`.
    private func rewriteEnumConstructorPropertyCall(
        instruction: KIRInstruction,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) -> [KIRInstruction]? {
        let prefix = "$enumConstructorProperty$"
        guard case let .call(symbol, callee, arguments, result, _, _, _, _) = instruction,
              symbol == nil,
              arguments.count == 1,
              interner.resolve(callee).hasPrefix(prefix)
        else {
            return nil
        }

        let remainder = String(interner.resolve(callee).dropFirst(prefix.count))
        guard let separatorIndex = remainder.firstIndex(of: "$"),
              let classID = Int32(remainder[..<separatorIndex]),
              !remainder[remainder.index(after: separatorIndex)...].isEmpty
        else {
            return nil
        }
        let propertyName = interner.intern(String(remainder[remainder.index(after: separatorIndex)...]))
        let classSymbol = SymbolID(rawValue: classID)
        guard let classSym = sema.symbols.symbol(classSymbol),
              classSym.kind == .enumClass
        else {
            return nil
        }

        let propSymbol = sema.symbols.lookupAll(fqName: classSym.fqName + [propertyName])
            .first { id in
                sema.symbols.symbol(id).map { $0.kind == .property } ?? false
            }
        let propType = propSymbol.flatMap { sema.symbols.propertyType(for: $0) } ?? sema.types.anyType

        // The placeholder callee embeds the caller-side class symbol rawValue,
        // which is re-assigned across .kklib boundaries. The synthesized helper
        // is registered under a stable, ID-free name scoped by the enum fqName.
        let helperName = interner.intern("\(prefix)\(interner.resolve(propertyName))")
        let helperSymbol = sema.symbols.lookupAll(fqName: classSym.fqName + [helperName])
            .first { id in
                sema.symbols.symbol(id).map { $0.kind == .function } ?? false
            }
        guard let helperSymbol else { return nil }

        let targetResult = result ?? arena.appendTemporary(type: propType)
        return [.call(
            symbol: helperSymbol,
            callee: helperName,
            arguments: [arguments[0]],
            result: targetResult,
            canThrow: false,
            thrownResult: nil,
            isSuperCall: false
        )]
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

/// BUG-A/BUG-Planet: resolves the function that should render `classSym`'s
/// enum values as strings when a user `toString()` override exists, so
/// callers can prefer it over the default `$enumOrdinalToName` bare-name
/// rendering. Checked in order:
///  1. A direct, non-synthetic `toString()` declared on the enum class body
///     itself (e.g. `enum class Planet { ...; override fun toString() = ... }`).
///  2. The per-entry dispatch helper for `kotlin.Enum.toString()`, reached
///     when at least one entry body overrides `toString()` (e.g. `Op.MUL`'s
///     `override fun toString() = "times"`). `EnumEntryBodyHeaders` registers
///     this helper under the enum class's own fqName, keyed by the shared
///     `Enum.toString` base symbol's mangled name, so looking it up this way
///     stays correct even when multiple enum classes in the same
///     compilation each register their own dispatch for that shared base --
///     a lookup keyed by the base symbol alone could not tell them apart.
/// Returns `nil` when neither exists, meaning the default rendering applies.
/// Takes the raw `SymbolTable` (rather than `SemaModule`) so it is usable
/// from both KIR lowering passes and the lower-level call-emission helpers.
func enumToStringOverrideHelper(
    for classSym: SemanticSymbol,
    symbols: SymbolTable,
    interner: StringInterner
) -> (symbol: SymbolID, name: InternedString)? {
    let toStringName = interner.intern("toString")
    // A direct, non-synthetic `toString()` on the class body itself is the
    // *default* implementation entries fall through to -- but when some
    // entry bodies ALSO override toString(), `EnumEntryBodyHeaders` keys
    // their dispatch helper off this class-level symbol (not
    // `kotlin.Enum.toString`, since `duplicatesDirectMember` prefers the
    // direct member as the dispatch base). Prefer that helper when present:
    // it already runs the per-entry switch and falls back to this same
    // class-level symbol for every non-overriding entry, so returning the
    // plain override here instead would silently ignore an entry's own
    // override (`enum class X { A { override fun toString() = "a!" }, B;
    // override fun toString() = "x-" + name }` must print "a!" then "x-B").
    if let directOverride = symbols.lookupAll(fqName: classSym.fqName + [toStringName]).first(where: { id in
        guard let info = symbols.symbol(id),
              info.kind == .function,
              !info.flags.contains(.synthetic)
        else {
            return false
        }
        return symbols.parentSymbol(for: id) == classSym.id
    }), let directOverrideInfo = symbols.symbol(directOverride) {
        let dispatchHelperName = NameMangler.enumEntryDispatchHelperName(for: directOverrideInfo, interner: interner)
        if let dispatchSymbol = symbols.lookupAll(fqName: classSym.fqName + [dispatchHelperName]).first(where: { id in
            symbols.symbol(id).map { $0.kind == .function } ?? false
        }) {
            return (dispatchSymbol, dispatchHelperName)
        }
        return (directOverride, toStringName)
    }
    guard let enumBaseToString = symbols.lookup(
        fqName: [interner.intern("kotlin"), interner.intern("Enum"), toStringName]
    ),
    let enumBaseToStringInfo = symbols.symbol(enumBaseToString)
    else {
        return nil
    }
    let dispatchHelperName = NameMangler.enumEntryDispatchHelperName(for: enumBaseToStringInfo, interner: interner)
    guard let dispatchSymbol = symbols.lookupAll(fqName: classSym.fqName + [dispatchHelperName]).first(where: { id in
        symbols.symbol(id).map { $0.kind == .function } ?? false
    }) else {
        return nil
    }
    return (dispatchSymbol, dispatchHelperName)
}
