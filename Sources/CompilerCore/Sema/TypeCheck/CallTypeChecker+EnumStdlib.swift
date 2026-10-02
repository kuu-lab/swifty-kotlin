
enum EnumStdlibSpecialCallResult {
    case enumValues(enumType: TypeID, arrayType: TypeID, stubSymbol: SymbolID)
    case enumValueOf(enumType: TypeID, stubSymbol: SymbolID)
    case enumEntries(enumType: TypeID, entriesType: TypeID, stubSymbol: SymbolID)
}

extension CallTypeChecker {
    func enumStdlibSpecialCallKind(
        calleeName: InternedString,
        args: [CallArgument],
        explicitTypeArgs: [TypeID],
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        interner: StringInterner,
        sema: SemaModule,
        range: SourceRange
    ) -> EnumStdlibSpecialCallResult? {
        let (visibleCandidates, _) = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName))
        guard let intrinsic = visibleCandidates.compactMap({
            sema.wellKnownSymbols.enumIntrinsic(for: $0)
        }).first,
        let stubSymbol = visibleCandidates.first(where: {
            sema.wellKnownSymbols.enumIntrinsic(for: $0) == intrinsic
        }) else {
            return nil
        }
        let hasNonSyntheticUserCandidate = visibleCandidates.contains { candidate in
            guard let symbol = ctx.cachedSymbol(candidate) else {
                return false
            }
            if symbol.flags.contains(.synthetic) {
                return false
            }
            // The well-known table identifies the bundled/imported declaration
            // itself. Any other non-synthetic visible candidate is a user
            // declaration and must shadow the intrinsic path.
            return sema.wellKnownSymbols.enumIntrinsic(for: candidate) == nil
        }
        if locals[calleeName] != nil || hasNonSyntheticUserCandidate {
            return nil
        }
        guard explicitTypeArgs.count == 1 else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "Expected exactly one type argument for `\(interner.resolve(calleeName))`.",
                range: range
            )
            return nil
        }
        let typeArg = explicitTypeArgs[0]
        guard case let .classType(classType) = sema.types.kind(of: typeArg),
              classType.nullability == .nonNull,
              let nominalSymbol = sema.symbols.symbol(classType.classSymbol),
              nominalSymbol.kind == .enumClass
        else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "`\(interner.resolve(calleeName))` requires exactly one non-nullable enum type argument.",
                range: range
            )
            return nil
        }

        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: classType.classSymbol,
            args: [],
            nullability: .nonNull
        )))

        switch intrinsic {
        case .enumValues:
            guard args.isEmpty else {
                return nil
            }
            let arraySymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("Array"),
            ])
            guard let arraySymbol else {
                return nil
            }
            let arrayType = sema.types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(enumType)],
                nullability: .nonNull
            )))
            return .enumValues(enumType: enumType, arrayType: arrayType, stubSymbol: stubSymbol)

        case .enumValueOf:
            guard args.count == 1 else {
                return nil
            }
            return .enumValueOf(enumType: enumType, stubSymbol: stubSymbol)

        case .enumEntries, .enumEntriesIntrinsic:
            guard args.isEmpty else {
                return nil
            }
            let enumEntriesInterfaceSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("enums"),
                interner.intern("EnumEntries"),
            ])
            guard let enumEntriesInterfaceSymbol else {
                return nil
            }
            let entriesType = sema.types.make(.classType(ClassType(
                classSymbol: enumEntriesInterfaceSymbol,
                args: [.invariant(enumType)],
                nullability: .nonNull
            )))
            return .enumEntries(enumType: enumType, entriesType: entriesType, stubSymbol: stubSymbol)
        }
    }
}
