
/// Runs after DataEnumSealedSynthesisPass which creates the `entries$get` helper.
final class EnumEntriesLoweringPass: LoweringPass, ParallelLoweringPass {
    static let name = "EnumEntriesLowering"
    static let requiredStage: KIRStage = .propertyLowered
    static let producedStage: KIRStage = .propertyLowered

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }
        let entriesName = ctx.interner.intern("entries")
        let entriesGetName = ctx.interner.intern("entries$get")

        module.arena.transformFunctions { function in
            var newBody = KIRLoweringEmitContext()
            for (index, instruction) in function.body.enumerated() {
                newBody.currentSourceRange = index < function.instructionLocations.count
                    ? function.instructionLocations[index]
                    : nil
                if let rewritten = self.rewriteEntriesAccess(
                    instruction: instruction,
                    sema: sema,
                    arena: module.arena,
                    entriesName: entriesName,
                    entriesGetName: entriesGetName
                ) {
                    newBody.append(rewritten)
                    continue
                }
                if let rewritten = self.rewriteEntriesConstValue(
                    instruction: instruction,
                    sema: sema,
                    arena: module.arena,
                    entriesName: entriesName,
                    entriesGetName: entriesGetName
                ) {
                    newBody.append(rewritten)
                    continue
                }
                if let rewritten = self.rewriteEntriesLoadGlobal(
                    instruction: instruction,
                    sema: sema,
                    arena: module.arena,
                    entriesName: entriesName,
                    entriesGetName: entriesGetName
                ) {
                    newBody.append(rewritten)
                    continue
                }
                newBody.append(instruction)
            }
            var updated = function
            updated.replaceBody(newBody)
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func rewriteEntriesAccess(
        instruction: KIRInstruction,
        sema: SemaModule,
        arena: KIRArena,
        entriesName: InternedString,
        entriesGetName: InternedString
    ) -> KIRInstruction? {
        guard case let .call(symbol, _, _, result, _, _, _, _) = instruction,
              let propSym = symbol,
              let propInfo = sema.symbols.symbol(propSym),
              propInfo.kind == .property,
              propInfo.name == entriesName
        else {
            return nil
        }
        guard let getter = entriesGetFunctionSymbol(
            forPropertySymbol: propSym,
            sema: sema,
            entriesGetName: entriesGetName
        ) else {
            return nil
        }
        let targetResult = normalizePropertyResult(
            result,
            propertySymbol: propSym,
            arena: arena
        ) ?? arena.appendTemporary(type: sema.types.anyType)
        return .call(symbol: getter, callee: entriesGetName, arguments: [], result: targetResult, canThrow: false)
    }

    /// BuildKIR may emit `constValue(result, .symbolRef(entriesPropSym))` for
    /// property references in some code paths.
    private func rewriteEntriesConstValue(
        instruction: KIRInstruction,
        sema: SemaModule,
        arena: KIRArena,
        entriesName: InternedString,
        entriesGetName: InternedString
    ) -> KIRInstruction? {
        guard case let .constValue(cvResult, value) = instruction,
              case let .symbolRef(sym) = value,
              let symInfo = sema.symbols.symbol(sym),
              symInfo.kind == .property,
              symInfo.name == entriesName
        else {
            return nil
        }
        guard let getter = entriesGetFunctionSymbol(
            forPropertySymbol: sym,
            sema: sema,
            entriesGetName: entriesGetName
        ) else {
            return nil
        }
        _ = normalizePropertyResult(cvResult, propertySymbol: sym, arena: arena)
        return .call(symbol: getter, callee: entriesGetName, arguments: [], result: cvResult, canThrow: false)
    }

    /// BuildKIR emits `loadGlobal(result, entriesPropSym)` when the companion's
    /// `entries` property is accessed as a global variable load instead of a
    /// getter call.
    private func rewriteEntriesLoadGlobal(
        instruction: KIRInstruction,
        sema: SemaModule,
        arena: KIRArena,
        entriesName: InternedString,
        entriesGetName: InternedString
    ) -> KIRInstruction? {
        guard case let .loadGlobal(result, symbol) = instruction,
              let symInfo = sema.symbols.symbol(symbol),
              symInfo.kind == .property,
              symInfo.name == entriesName
        else {
            return nil
        }
        guard let getter = entriesGetFunctionSymbol(
            forPropertySymbol: symbol,
            sema: sema,
            entriesGetName: entriesGetName
        ) else {
            return nil
        }
        let normalizedResult = normalizePropertyResult(
            result,
            propertySymbol: symbol,
            arena: arena
        )
        return .call(symbol: getter, callee: entriesGetName, arguments: [], result: normalizedResult, canThrow: false)
    }

    /// The helper may be registered under either the enum class's or the
    /// companion's fqName, so both are tried in that order.
    private func entriesGetFunctionSymbol(
        forPropertySymbol propertySymbol: SymbolID,
        sema: SemaModule,
        entriesGetName: InternedString
    ) -> SymbolID? {
        guard let enumClassSymbol = findOwnerEnumClass(for: propertySymbol, sema: sema),
              let classSym = sema.symbols.symbol(enumClassSymbol)
        else {
            return nil
        }
        let getterFQName = classSym.fqName + [entriesGetName]
        let companionFQName = sema.symbols.companionObjectSymbol(for: enumClassSymbol)
            .flatMap { sema.symbols.symbol($0)?.fqName }
        return sema.symbols.lookupAll(fqName: getterFQName).first(where: { id in
            sema.symbols.symbol(id).map { $0.kind == .function } ?? false
        }) ?? companionFQName.flatMap { fq in
            sema.symbols.lookupAll(fqName: fq + [entriesGetName]).first(where: { id in
                sema.symbols.symbol(id).map { $0.kind == .function } ?? false
            })
        }
    }

    private func normalizePropertyResult(
        _ result: KIRExprID?,
        propertySymbol: SymbolID,
        arena: KIRArena
    ) -> KIRExprID? {
        guard let result,
              case let .symbolRef(referencedSymbol) = arena.expr(result),
              referencedSymbol == propertySymbol
        else {
            return result
        }
        arena.replaceExpr(result, with: .temporary(result.rawValue))
        return result
    }

    /// The property may be directly on the enum class, or on its companion object.
    private func findOwnerEnumClass(for symbol: SymbolID, sema: SemaModule) -> SymbolID? {
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
