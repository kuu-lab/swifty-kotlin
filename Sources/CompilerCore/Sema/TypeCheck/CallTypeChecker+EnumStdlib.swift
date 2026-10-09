
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
        knownNames: KnownCompilerNames,
        sema: SemaModule,
        range: SourceRange
    ) -> EnumStdlibSpecialCallResult? {
        // Cheap interned-ID bail: only the four enum intrinsic spellings —
        // or a file-local import alias of one (`import kotlin.enumValueOf as
        // evo` binds the same SymbolID) — can resolve to a well-known enum
        // intrinsic, so every other unqualified call exits before the scope
        // lookup below.
        guard calleeName == knownNames.enumValues
            || calleeName == knownNames.enumValueOf
            || calleeName == knownNames.enumEntries
            || calleeName == knownNames.enumEntriesIntrinsic
            || isEnumIntrinsicImportAlias(calleeName, ctx: ctx, knownNames: knownNames)
        else {
            return nil
        }
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
        let enumType: TypeID
        if case let .classType(classType) = sema.types.kind(of: typeArg),
           classType.nullability == .nonNull,
           sema.symbols.symbol(classType.classSymbol)?.kind == .enumClass {
            enumType = typeArg
        } else if intrinsic == .enumValues,
                  case let .typeParam(parameter) = sema.types.kind(of: typeArg),
                  parameter.nullability == .nonNull,
                  sema.symbols.symbol(parameter.symbol)?.flags.contains(.reifiedTypeParameter) == true,
                  let enumSymbol = sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Enum")]),
                  sema.symbols.typeParameterUpperBounds(for: parameter.symbol).contains(where: { bound in
                      guard case let .classType(boundClass) = sema.types.kind(of: bound),
                            boundClass.classSymbol == enumSymbol,
                            boundClass.nullability == .nonNull,
                            boundClass.args == [.invariant(typeArg)] else { return false }
                      return true
                  }) {
            enumType = typeArg
        } else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "`\(interner.resolve(calleeName))` requires exactly one non-nullable enum type argument.",
                range: range
            )
            return nil
        }

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

    /// Whether `calleeName` is an import alias in the current file for one of
    /// the enum intrinsic FQ names. The alias resolves to the intrinsic's
    /// SymbolID, so aliased calls must reach the scope lookup above. The
    /// alias-name set is computed once per file and memoized on `SemaModule`.
    private func isEnumIntrinsicImportAlias(
        _ calleeName: InternedString,
        ctx: TypeInferenceContext,
        knownNames: KnownCompilerNames
    ) -> Bool {
        let fileID = ctx.currentFileID
        let aliasNames: Set<InternedString>
        if let cached = ctx.sema.enumIntrinsicAliasNamesByFile[fileID] {
            aliasNames = cached
        } else {
            var names = Set<InternedString>()
            for importDecl in ctx.currentASTFile?.imports ?? [] {
                guard let alias = importDecl.alias,
                      knownNames.enumIntrinsicFQNames.contains(importDecl.path)
                else { continue }
                names.insert(alias)
            }
            ctx.sema.enumIntrinsicAliasNamesByFile[fileID] = names
            aliasNames = names
        }
        return aliasNames.contains(calleeName)
    }
}
