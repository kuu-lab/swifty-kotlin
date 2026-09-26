extension DataFlowSemaPhase {
    /// Registers enum-entry dispatch helpers after inheritance edges are bound.
    /// Entry overrides may implement a function inherited from an interface, so
    /// the complete base-member set is unavailable during ordinary header collection.
    func registerAllEnumEntryDispatchFunctions(
        ast: ASTModule,
        bindings: BindingTable,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            registerEnumEntryDispatchFunctions(
                in: file.topLevelDecls,
                ast: ast,
                bindings: bindings,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }

    private func registerEnumEntryDispatchFunctions(
        in declIDs: [DeclID],
        ast: ASTModule,
        bindings: BindingTable,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        for declID in declIDs {
            guard let decl = ast.arena.decl(declID) else { continue }

            let nestedDeclIDs: [DeclID]
            switch decl {
            case let .classDecl(classDecl):
                nestedDeclIDs = classDecl.nestedClasses + classDecl.nestedObjects
                    + (classDecl.companionObject.map { [$0] } ?? [])
                if let symbol = bindings.declSymbols[declID],
                   symbols.symbol(symbol)?.kind == .enumClass,
                   let symbolInfo = symbols.symbol(symbol)
                {
                    let enumType = types.make(.classType(ClassType(
                        classSymbol: symbol,
                        args: [],
                        nullability: .nonNull
                    )))
                    registerEnumEntryDispatchFunctions(
                        entries: classDecl.enumEntries,
                        memberFunctions: classDecl.memberFunctions,
                        ownerFQName: symbolInfo.fqName,
                        ownerSymbol: symbol,
                        enumType: enumType,
                        ast: ast,
                        bindings: bindings,
                        symbols: symbols,
                        types: types,
                        interner: interner
                    )
                }
            case let .interfaceDecl(interfaceDecl):
                nestedDeclIDs = interfaceDecl.nestedClasses + interfaceDecl.nestedObjects
                    + (interfaceDecl.companionObject.map { [$0] } ?? [])
            case let .objectDecl(objectDecl):
                nestedDeclIDs = objectDecl.nestedClasses + objectDecl.nestedObjects
            default:
                continue
            }

            registerEnumEntryDispatchFunctions(
                in: nestedDeclIDs,
                ast: ast,
                bindings: bindings,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }

    /// Registers functions declared in an enum entry body under the entry field
    /// symbol. Keeping the entry field as the semantic owner prevents these
    /// functions from becoming ordinary enum members while still giving them
    /// the enum type as their receiver representation.
    func collectEnumEntryMemberHeaders(
        entries: [EnumEntryDecl],
        ownerFQName: [InternedString],
        ownerSymbol: SymbolID,
        enumType: TypeID,
        sourceFileID: FileID,
        ctx: CompilationContext,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        scope: Scope,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        classTypeParameterSymbols: [SymbolID] = [],
        classLocalTypeParameters: [InternedString: SymbolID] = [:]
    ) {
        for entry in entries where !entry.memberFunctions.isEmpty {
            let entryFQName = ownerFQName + [entry.name]
            guard let entrySymbol = symbols.lookupAll(fqName: entryFQName).first(where: { symbolID in
                symbols.symbol(symbolID)?.kind == .field
                    && symbols.parentSymbol(for: symbolID) == ownerSymbol
            }) else {
                continue
            }

            let entryScope = ClassMemberScope(
                parent: scope,
                symbols: symbols,
                ownerSymbol: entrySymbol,
                thisType: enumType
            )
            collectMemberHeaders(
                members: MemberDeclarations(
                    functions: entry.memberFunctions,
                    properties: [],
                    nestedClasses: [],
                    nestedObjects: []
                ),
                owner: OwnerContext(
                    fqName: entryFQName,
                    symbol: entrySymbol,
                    type: enumType
                ),
                sourceFileID: sourceFileID,
                ctx: ctx,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: entryScope,
                diagnostics: diagnostics,
                interner: interner,
                classTypeParameterSymbols: classTypeParameterSymbols,
                classLocalTypeParameters: classLocalTypeParameters
            )
        }
    }

    /// Creates the semantic symbols used by KIR to dispatch an enum-typed call
    /// to the matching entry-body override. The helper is registered after
    /// inheritance edges are bound so inherited interface members are included.
    func registerEnumEntryDispatchFunctions(
        entries: [EnumEntryDecl],
        memberFunctions: [DeclID],
        ownerFQName: [InternedString],
        ownerSymbol: SymbolID,
        enumType: TypeID,
        ast: ASTModule,
        bindings: BindingTable,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        var baseFunctions: [SymbolID] = memberFunctions.compactMap { declID in
            guard let decl = ast.arena.decl(declID),
                  case .funDecl = decl,
                  let symbol = bindings.declSymbols[declID],
                  let symbolInfo = symbols.symbol(symbol),
                  symbolInfo.kind == .function,
                  symbols.parentSymbol(for: symbol) == ownerSymbol
            else {
                return nil
            }
            return symbol
        }

        // Include inherited members (most importantly interface methods) that
        // member lookup can select for an enum-typed receiver. Keep a direct
        // member's signature as the preferred base when it overrides the same
        // inherited declaration.
        //
        // BUG-A: a base function inherited through a *generic* supertype (the
        // implicit `kotlin.Enum<T>` every enum class extends) declares its
        // receiver in terms of Enum's own unsubstituted type parameter `T`,
        // not the concrete enum class. `Enum<T>` and the concrete `enumType`
        // (e.g. `Op`) are unrelated types by naive comparison, so `toString()`
        // silently never became a dispatch target and an entry-body
        // `override fun toString()` was ignored. Substitute each candidate's
        // receiver type using the recorded supertype type args (`Enum<Op>`
        // for `Op`) before the match below compares it against `enumType`.
        var effectiveReceiverTypes: [SymbolID: TypeID] = [:]
        var pendingSupertypes = symbols.directSupertypes(for: ownerSymbol)
        var visitedSupertypes: Set<SymbolID> = []
        while let supertype = pendingSupertypes.popLast() {
            guard visitedSupertypes.insert(supertype).inserted else { continue }
            if let supertypeInfo = symbols.symbol(supertype) {
                let supertypeArgs = symbols.supertypeTypeArgs(for: ownerSymbol, supertype: supertype)
                for candidate in symbols.children(ofFQName: supertypeInfo.fqName) {
                    guard let candidateInfo = symbols.symbol(candidate),
                          candidateInfo.kind == .function,
                          let candidateSignature = symbols.functionSignature(for: candidate)
                    else {
                        continue
                    }
                    let duplicatesDirectMember = baseFunctions.contains { direct in
                        guard let directInfo = symbols.symbol(direct),
                              let directSignature = symbols.functionSignature(for: direct)
                        else {
                            return false
                        }
                        return directInfo.name == candidateInfo.name
                            && directSignature.parameterTypes == candidateSignature.parameterTypes
                            && directSignature.isSuspend == candidateSignature.isSuspend
                    }
                    if !duplicatesDirectMember {
                        baseFunctions.append(candidate)
                        if let receiverType = candidateSignature.receiverType, !supertypeArgs.isEmpty {
                            effectiveReceiverTypes[candidate] = types.substituteNominalTypeParameters(
                                in: receiverType, owner: supertype, ownerArgs: supertypeArgs
                            )
                        }
                    }
                }
            }
            pendingSupertypes.append(contentsOf: symbols.directSupertypes(for: supertype))
        }

        var targetsByBase: [SymbolID: [EnumEntryDispatchTarget]] = [:]
        for entry in entries {
            let entryFQName = ownerFQName + [entry.name]
            guard let entrySymbol = symbols.lookupAll(fqName: entryFQName).first(where: { symbolID in
                symbols.symbol(symbolID)?.kind == .field
                    && symbols.parentSymbol(for: symbolID) == ownerSymbol
            }) else {
                continue
            }

            for declID in entry.memberFunctions {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      function.modifiers.contains(.override),
                      let bodySymbol = bindings.declSymbols[declID],
                      let bodySignature = symbols.functionSignature(for: bodySymbol)
                else {
                    continue
                }
                let candidates = baseFunctions.filter { candidate in
                    guard let candidateSignature = symbols.functionSignature(for: candidate),
                          let rawReceiverType = candidateSignature.receiverType
                    else {
                        return false
                    }
                    let candidateReceiverType = effectiveReceiverTypes[candidate] ?? rawReceiverType
                    guard receiverMatchesEnum(
                              candidateReceiverType,
                              enumType: enumType,
                              enumSymbol: ownerSymbol,
                              types: types
                          ),
                          bodySignature.receiverType == enumType,
                          // BUG-A: `typeParameterSymbols` also carries the
                          // *enclosing class's* own type parameters for a
                          // generic base like `kotlin.Enum<T>` (see
                          // `classTypeParameterCount`'s doc comment) -- only
                          // reject a candidate with type parameters of its
                          // own, not inherited class-level ones already
                          // accounted for by the receiver-type substitution
                          // above.
                          candidateSignature.typeParameterSymbols.count == candidateSignature.classTypeParameterCount,
                          candidateSignature.reifiedTypeParameterIndices.isEmpty,
                          !candidateSignature.isSuspend,
                          bodySignature.typeParameterSymbols.count
                              == bodySignature.classTypeParameterCount,
                          bodySignature.reifiedTypeParameterIndices.isEmpty,
                          !bodySignature.isSuspend,
                          candidateSignature.parameterTypes == bodySignature.parameterTypes
                    else {
                        return false
                    }
                    return symbols.symbol(candidate)?.name == function.name
                }
                // Multiple interfaces may contribute the same signature. Keep
                // the target on every matching base symbol so whichever
                // declaration overload resolution selects still reaches the
                // entry implementation.
                for matchingBase in candidates {
                    targetsByBase[matchingBase, default: []].append(
                        EnumEntryDispatchTarget(entrySymbol: entrySymbol, functionSymbol: bodySymbol)
                    )
                }
            }
        }

        for (baseSymbol, targets) in targetsByBase {
            guard let baseInfo = symbols.symbol(baseSymbol),
                  let baseSignature = symbols.functionSignature(for: baseSymbol)
            else {
                continue
            }
            let helperName = NameMangler.enumEntryDispatchHelperName(
                for: baseInfo,
                interner: interner
            )
            let helperFQName = ownerFQName + [helperName]
            let helperSymbol = symbols.lookupAll(fqName: helperFQName).first(where: { symbolID in
                symbols.symbol(symbolID)?.kind == .function
                    && symbols.parentSymbol(for: symbolID) == ownerSymbol
            }) ?? symbols.define(
                kind: .function,
                name: helperName,
                fqName: helperFQName,
                declSite: baseInfo.declSite,
                visibility: .private,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(ownerSymbol, for: helperSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: enumType,
                    parameterTypes: baseSignature.parameterTypes,
                    returnType: baseSignature.returnType,
                    isSuspend: baseSignature.isSuspend,
                    canThrow: baseSignature.canThrow,
                    valueParameterSymbols: baseSignature.valueParameterSymbols,
                    valueParameterHasDefaultValues: baseSignature.valueParameterHasDefaultValues,
                    valueParameterIsVararg: baseSignature.valueParameterIsVararg,
                    valueParameterAllowsNonLocalReturn: baseSignature.valueParameterAllowsNonLocalReturn,
                    typeParameterSymbols: baseSignature.typeParameterSymbols,
                    reifiedTypeParameterIndices: baseSignature.reifiedTypeParameterIndices,
                    typeParameterUpperBounds: baseSignature.typeParameterUpperBounds,
                    typeParameterUpperBoundsList: baseSignature.typeParameterUpperBoundsList,
                    classTypeParameterCount: baseSignature.classTypeParameterCount
                ),
                for: helperSymbol
            )
            symbols.setEnumEntryDispatchTargets(targets, for: helperSymbol)
            symbols.setEnumEntryDispatchBaseSymbol(baseSymbol, for: helperSymbol)
        }
    }

    /// Whether calls on an enum-typed receiver can resolve to a member whose
    /// declared receiver is `candidateReceiverType`. An inherited member
    /// (e.g. `kotlin.Enum<T>.toString`) keeps the declaring class's generic
    /// receiver, which `isSubtype` rejects against the concrete enum, so the
    /// erased nominal ancestry is the right granularity for dispatch.
    private func receiverMatchesEnum(
        _ candidateReceiverType: TypeID,
        enumType: TypeID,
        enumSymbol: SymbolID,
        types: TypeSystem
    ) -> Bool {
        if candidateReceiverType == enumType
            || types.isSubtype(enumType, candidateReceiverType)
        {
            return true
        }
        guard case let .classType(classType) = types.kind(of: candidateReceiverType) else {
            return false
        }
        return types.isNominalSubtypeSymbol(enumSymbol, of: classType.classSymbol)
    }
}
