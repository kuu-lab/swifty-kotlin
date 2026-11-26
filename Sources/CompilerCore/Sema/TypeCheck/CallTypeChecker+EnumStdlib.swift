
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
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        interner: StringInterner,
        knownNames: KnownCompilerNames,
        sema: SemaModule,
        range: SourceRange
    ) -> EnumStdlibSpecialCallResult? {
        guard calleeName == knownNames.enumValues
            || calleeName == knownNames.enumValueOf
            || calleeName == knownNames.enumEntries
            || calleeName == knownNames.enumEntriesIntrinsic
            || isEnumIntrinsicImportAlias(calleeName, ctx: ctx, knownNames: knownNames)
        else {
            return nil
        }
        let explicitlyImportedCandidates = explicitlyImportedEnumIntrinsicCandidates(
            named: calleeName,
            ctx: ctx,
            knownNames: knownNames,
            sema: sema
        )
        let visibleCandidates: [SymbolID]
        if explicitlyImportedCandidates.isEmpty {
            let visible = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
            visibleCandidates = visible.isEmpty
                ? ctx.filterByVisibility(ctx.scope.lookupMergingChain(calleeName)).visible
                : visible
        } else {
            // The ordinary scope chain puts same-package declarations ahead of
            // explicit imports. Kotlin gives an explicit import priority here,
            // so use the imported intrinsic tier before checking for a user
            // declaration that would shadow the default-import intrinsic.
            visibleCandidates = explicitlyImportedCandidates
        }
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
            return sema.wellKnownSymbols.enumIntrinsic(for: candidate) == nil
        }
        if locals[calleeName] != nil || hasNonSyntheticUserCandidate {
            return nil
        }
        let typeArg: TypeID
        if resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs) == nil,
           intrinsic == .enumValues, args.isEmpty
        {
            let resolved = ctx.resolver.resolveCall(
                candidates: [stubSymbol],
                call: CallExpr(range: range, calleeName: calleeName, args: []),
                expectedType: expectedType,
                ctx: sema
            )
            guard resolved.chosenCallee == stubSymbol,
                  let inferred = resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)]
            else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "Cannot infer enum type argument for `\(interner.resolve(calleeName))` from the expected type.",
                    range: range
                )
                return nil
            }
            typeArg = inferred
        } else if explicitTypeArgs.count == 1,
                  let explicitTypeArg = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs)
        {
            typeArg = explicitTypeArg
        } else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "Expected exactly one type argument for `\(interner.resolve(calleeName))`.",
                range: range
            )
            return nil
        }
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
            ctx.sema.diagnostics.error(
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

    private func explicitlyImportedEnumIntrinsicCandidates(
        named calleeName: InternedString,
        ctx: TypeInferenceContext,
        knownNames: KnownCompilerNames,
        sema: SemaModule
    ) -> [SymbolID] {
        let importedPaths = Set((ctx.currentASTFile?.imports ?? []).compactMap { importDecl -> [InternedString]? in
            guard !importDecl.isWildcard,
                  (importDecl.alias ?? importDecl.path.last) == calleeName,
                  knownNames.enumIntrinsicFQNames.contains(importDecl.path)
            else {
                return nil
            }
            return importDecl.path
        })
        guard !importedPaths.isEmpty else {
            return []
        }

        let candidates = ctx.scope.lookupMergingChain(calleeName).filter { candidate in
            guard let symbol = ctx.cachedSymbol(candidate) else {
                return false
            }
            return importedPaths.contains(symbol.fqName)
                && sema.wellKnownSymbols.enumIntrinsic(for: candidate) != nil
        }
        return ctx.filterByVisibility(candidates).visible
    }
}
