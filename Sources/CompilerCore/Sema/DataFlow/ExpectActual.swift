import Foundation

/// Source declarations keyed by their symbol's decl-site range, used to tell
/// whether an actual member still carries a header placeholder type because
/// its real type will only be inferred during body analysis.
struct ExpectActualSourceDeclarations {
    var functionsByRange: [SourceRange: [FunDecl]] = [:]
    var propertiesByRange: [SourceRange: [PropertyDecl]] = [:]
}

extension DataFlowSemaPhase {
    /// Convenience entry point for unit tests that exercise matching without a
    /// following type-check pass; provisionally-linked pairs are dropped
    /// instead of re-verified.
    func validateExpectActualMatching(
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        commonModuleMode: Bool
    ) {
        var deferred: [(expect: SymbolID, actual: SymbolID)] = []
        validateExpectActualMatching(
            ast: ast,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            commonModuleMode: commonModuleMode,
            deferredInferredTypePairs: &deferred
        )
    }

    func validateExpectActualMatching(
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        commonModuleMode: Bool,
        deferredInferredTypePairs: inout [(expect: SymbolID, actual: SymbolID)]
    ) {
        // Common libraries preserve expect markers so a platform compilation can
        // pair them with local actual declarations. Other imported declarations
        // remain outside this validation unless they are marked expect.
        let expects = symbols.allSymbols().filter { sym in
            sym.flags.contains(.expectDeclaration)
                && (sym.declSite != nil || sym.flags.contains(.importedLibrary))
        }.map { symbol in
            (
                symbol: symbol,
                nestingDepth: expectActualNestingDepth(of: symbol.id, symbols: symbols)
            )
        }.sorted { lhs, rhs in
            if lhs.nestingDepth != rhs.nestingDepth {
                return lhs.nestingDepth < rhs.nestingDepth
            }
            return lhs.symbol.id.rawValue < rhs.symbol.id.rawValue
        }.map { $0.symbol }
        guard !expects.isEmpty else { return }
        let functionDeclarationsByRange = Dictionary(grouping: ast.arena.declarations().compactMap { decl -> FunDecl? in
            guard case let .funDecl(function) = decl else { return nil }
            return function
        }, by: \.range)
        var sourceDeclarations = ExpectActualSourceDeclarations(
            functionsByRange: functionDeclarationsByRange
        )
        sourceDeclarations.propertiesByRange = Dictionary(grouping: ast.arena.declarations().compactMap { decl -> PropertyDecl? in
            guard case let .propertyDecl(property) = decl else { return nil }
            return property
        }, by: \.range)
        for expectSym in expects {
            // Optional expectation applies to the annotation class and its members.
            var expectationOwner: SymbolID? = expectSym.id
            var isOptionalExpectation = false
            while let owner = expectationOwner {
                if symbols.annotations(for: owner).contains(where: {
                    KnownCompilerAnnotation.optionalExpectation.matches($0.annotationFQName)
                }) {
                    isOptionalExpectation = true
                    break
                }
                expectationOwner = symbols.parentSymbol(for: owner)
            }
            let actuals = symbols.lookupAll(fqName: expectSym.fqName)
                .compactMap { symbols.symbol($0) }
                .filter { actual in
                    guard actual.flags.contains(.actualDeclaration) else {
                        return false
                    }
                    if expectSym.flags.contains(.importedLibrary),
                       actual.flags.contains(.importedLibrary)
                    {
                        return false
                    }
                    return true
                }

            let aliasTargetMembers = actualTypeAliasMembers(
                for: expectSym,
                symbols: symbols,
                types: types
            )
            let aliasTargetMemberIDs = Set(aliasTargetMembers.map(\.id))
            let candidates = (actuals + aliasTargetMembers).filter { actual in
                actual.kind == expectSym.kind
                    || (expectSym.kind == .annotationClass && actual.kind == .typeAlias)
                    || (expectSym.kind == .class && actual.kind == .typeAlias)
            }
                .filter { actual in
                    actual.flags.contains(.actualDeclaration) || aliasTargetMemberIDs.contains(actual.id)
            }
                .sorted(by: { $0.id.rawValue < $1.id.rawValue })

            let compatibleCandidates = candidates.filter { actual in
                areExpectActualCompatible(
                    expect: expectSym,
                    actual: actual,
                    symbols: symbols,
                    types: types,
                    sourceDeclarations: sourceDeclarations,
                    allowDeferredInferredActualTypes: true                )
            }

            let rendered = expectSym.fqName
                .map { interner.resolve($0) }
                .joined(separator: ".")

            guard let actualSym = compatibleCandidates.first else {
                // Common source-set artifacts intentionally preserve expect
                // declarations for a platform compilation to match later.
                if commonModuleMode, actuals.isEmpty {
                    continue
                }

                guard !isOptionalExpectation else {
                    continue
                }

                let candidateCount = candidates.count
                let compatibleCount = compatibleCandidates.count

                var diagnosticMessage = "Missing matching 'actual' declaration for expect symbol '\(rendered)'."
                if candidateCount == 0 {
                    diagnosticMessage += " No actual candidates found with same FQ name."
                } else if compatibleCount == 0 {
                    diagnosticMessage += " Found \(candidateCount) actual candidates but none were compatible."
                }

                if !candidates.isEmpty {
                    let candidateKinds = candidates.map { "\($0.kind)" }.joined(separator: ", ")
                    diagnosticMessage += " Candidate kinds: [\(candidateKinds)]."
                }

                diagnostics.error(
                    "KSWIFTK-MPP-UNRESOLVED",
                    diagnosticMessage,
                    range: expectSym.declSite
                )
                continue
            }

            if compatibleCandidates.count > 1 {
                diagnostics.error(
                    "KSWIFTK-MPP-AMBIGUOUS",
                    "Multiple matching 'actual' declarations found for expect symbol '\(rendered)'.",
                    range: expectSym.declSite
                )
                continue
            }

            symbols.setExpectActualLink(expect: expectSym.id, actual: actualSym.id)
            if isDeferredInferredTypePair(
                expect: expectSym,
                actual: actualSym,
                sourceDeclarations: sourceDeclarations,
                symbols: symbols,
                types: types
            ) {
                // The link was made while the actual's type was still a header
                // placeholder; body analysis publishes the inferred type, after
                // which verifyDeferredExpectActualTypes re-checks it for real.
                deferredInferredTypePairs.append((expect: expectSym.id, actual: actualSym.id))
            }
            inheritAbstractActualMemberFlags(
                expectOwner: expectSym,
                actualOwner: actualSym,
                functionDeclarationsByRange: functionDeclarationsByRange,
                symbols: symbols,
                types: types
            )
        }
    }

    func validateInferredExpectActualPropertyTypes(
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let inferredPropertySymbols = propertySymbols(ast: ast, symbols: symbols) { $0.type == nil }
        guard !inferredPropertySymbols.isEmpty else { return }

        for expect in symbols.allSymbols() where expect.flags.contains(.expectDeclaration)
            && (expect.kind == .property || expect.kind == .field)
        {
            guard let actualID = symbols.actualSymbol(for: expect.id),
                  inferredPropertySymbols.contains(actualID),
                  let actual = symbols.symbol(actualID),
                  let expectType = symbols.propertyType(for: expect.id),
                  let actualType = symbols.propertyType(for: actualID),
                  expectType != types.errorType,
                  actualType != types.errorType
            else {
                continue
            }

            let typeParamMapping = makeOwnerTypeParameterMapping(
                expect: expect,
                actual: actual,
                symbols: symbols,
                types: types
            )
            guard expect.flags.contains(.mutable) == actual.flags.contains(.mutable),
                  expectActualOptionalTypeMatch(
                      symbols.extensionPropertyReceiverType(for: expect.id),
                      symbols.extensionPropertyReceiverType(for: actual.id),
                      typeParamMapping: typeParamMapping,
                      symbols: symbols,
                      types: types
                  ),
                  !expectActualTypesMatch(
                      expectType,
                      actualType,
                      typeParamMapping: typeParamMapping,
                      symbols: symbols,
                      types: types
                  )
            else {
                continue
            }

            let rendered = expect.fqName.map { interner.resolve($0) }.joined(separator: ".")
            diagnostics.error(
                "KSWIFTK-MPP-UNRESOLVED",
                "Missing matching 'actual' declaration for expect symbol '\(rendered)'. The inferred actual property type is incompatible.",
                range: expect.declSite
            )
        }
    }

    private func propertySymbols(
        ast: ASTModule,
        symbols: SymbolTable,
        where predicate: (PropertyDecl) -> Bool
    ) -> Set<SymbolID> {
        Set(ast.arena.declarations().compactMap { declaration in
            guard case let .propertyDecl(property) = declaration,
                  predicate(property)
            else {
                return nil
            }
            return symbols.symbols(atDeclSite: property.range).first {
                symbols.symbol($0)?.kind == .property
            }
        })
    }

    private func inheritAbstractActualMemberFlags(
        expectOwner: SemanticSymbol,
        actualOwner: SemanticSymbol,
        functionDeclarationsByRange: [SourceRange: [FunDecl]],
        symbols: SymbolTable,
        types: TypeSystem
    ) {
        guard expectOwner.kind == .class,
              actualOwner.kind == .class,
              expectOwner.flags.contains(.abstractType),
              actualOwner.flags.contains(.abstractType)
        else {
            return
        }

        // Query only source functions of the matched abstract classes. Imported
        // shells have no AST body to inspect, and querying every symbol's parent
        // would force the entire lazy metadata library to materialize.
        let sourceFunctions = symbols.children(ofFQName: expectOwner.fqName)
            .compactMap { symbols.symbol($0) }
            .filter { $0.kind == .function && $0.declSite != nil }
        // Expect/actual classes share an FQ name, so verify the exact owner ID.
        let expectedFunctions = sourceFunctions.filter {
            symbols.parentSymbol(for: $0.id) == expectOwner.id
        }
        let actualFunctions = sourceFunctions.filter {
            $0.flags.contains(.actualDeclaration)
                && symbols.parentSymbol(for: $0.id) == actualOwner.id
        }

        for expectFunction in expectedFunctions {
            guard let expectDeclaration = functionDeclaration(
                for: expectFunction,
                in: functionDeclarationsByRange
            ), isBodylessNonRuntimeBridge(expectDeclaration),
                let expectSignature = symbols.functionSignature(for: expectFunction.id)
            else {
                continue
            }

            for actualFunction in actualFunctions where actualFunction.fqName == expectFunction.fqName {
                guard let actualDeclaration = functionDeclaration(
                    for: actualFunction,
                    in: functionDeclarationsByRange
                ), isBodylessNonRuntimeBridge(actualDeclaration),
                    let actualSignature = symbols.functionSignature(for: actualFunction.id),
                    expectActualFunctionSignaturesMatch(
                        expectSig: expectSignature,
                        expectSymbol: expectFunction,
                        actualSig: actualSignature,
                        actualSymbol: actualFunction,
                        symbols: symbols,
                        types: types
                    )
                else {
                    continue
                }

                // In an abstract expect class, a bodyless member is an abstract
                // contract even when the expect source omits the modifier. The
                // matching actual member inherits that modality in Kotlin MPP.
                symbols.insertFlags(.abstractType, for: actualFunction.id)
            }
        }
    }

    private func functionDeclaration(
        for symbol: SemanticSymbol,
        in declarationsByRange: [SourceRange: [FunDecl]]
    ) -> FunDecl? {
        guard let declSite = symbol.declSite else { return nil }
        return declarationsByRange[declSite]?.first { $0.name == symbol.name }
    }

    private func isBodylessNonRuntimeBridge(_ function: FunDecl) -> Bool {
        function.body == .unit
            && !function.modifiers.contains(.external)
            && !hasCompilerAnnotation(.ksSymbolName, on: function.annotations)
    }

    private func expectActualNestingDepth(of symbol: SymbolID, symbols: SymbolTable) -> Int {
        var depth = 0
        var current = symbols.parentSymbol(for: symbol)
        var visited: Set<SymbolID> = [symbol]
        while let parent = current, visited.insert(parent).inserted {
            depth += 1
            current = symbols.parentSymbol(for: parent)
        }
        return depth
    }

    private func actualTypeAliasMembers(
        for expectMember: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> [SemanticSymbol] {
        guard let expectOwnerID = symbols.parentSymbol(for: expectMember.id),
              let expectOwner = symbols.symbol(expectOwnerID),
              expectOwner.flags.contains(.expectDeclaration),
              let actualAliasID = symbols.actualSymbol(for: expectOwnerID),
              let actualAlias = symbols.symbol(actualAliasID),
              actualAlias.kind == .typeAlias,
              let actualOwnerID = actualTypeAliasTargetClassSymbol(
                  for: actualAlias,
                  symbols: symbols,
                  types: types
              ),
              let actualOwner = symbols.symbol(actualOwnerID)
        else {
            return []
        }

        let memberFQName = actualOwner.fqName + [expectMember.name]
        return symbols.lookupAll(fqName: memberFQName).compactMap { symbols.symbol($0) }
            .filter {
                $0.kind == expectMember.kind
                    && symbols.parentSymbol(for: $0.id) == actualOwnerID
            }
    }

    private func actualTypeAliasTargetClassSymbol(
        for alias: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> SymbolID? {
        var currentAlias = alias
        var visited: Set<SymbolID> = []
        while visited.insert(currentAlias.id).inserted,
              let underlyingType = symbols.typeAliasUnderlyingType(for: currentAlias.id),
              case let .classType(classType) = types.kind(of: underlyingType),
              classType.nullability == .nonNull,
              let target = symbols.symbol(classType.classSymbol)
        {
            guard target.kind == .typeAlias else {
                if target.flags.contains(.expectDeclaration),
                   let actualID = symbols.actualSymbol(for: target.id),
                   let actualTarget = symbols.symbol(actualID),
                   actualTarget.kind == .class
                {
                    return actualID
                }
                return target.kind == .class ? target.id : nil
            }
            currentAlias = target
        }
        return nil
    }

    /// Re-checks pairs whose link relied on a deferred inferred actual type.
    /// Runs after body analysis has published the real inferred types; any
    /// residual placeholder no longer gets the benefit of the doubt.
    func verifyDeferredExpectActualTypes(
        _ pairs: [(expect: SymbolID, actual: SymbolID)],
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for pair in pairs {
            guard let expectSym = symbols.symbol(pair.expect),
                  let actualSym = symbols.symbol(pair.actual)
            else {
                continue
            }
            guard areExpectActualCompatible(
                expect: expectSym,
                actual: actualSym,
                symbols: symbols,
                types: types
            ) else {
                let rendered = expectSym.fqName
                    .map { interner.resolve($0) }
                    .joined(separator: ".")
                diagnostics.error(
                    "KSWIFTK-MPP-UNRESOLVED",
                    "Missing matching 'actual' declaration for expect symbol '\(rendered)'. The actual declaration's inferred type is not compatible with the expect declaration.",
                    range: expectSym.declSite
                )
                continue
            }
        }
    }

    private func areExpectActualCompatible(
        expect: SemanticSymbol,
        actual: SemanticSymbol,
        allowInferredActualPropertyType: Bool = false,
        symbols: SymbolTable,
        types: TypeSystem,
        sourceDeclarations: ExpectActualSourceDeclarations = ExpectActualSourceDeclarations(),
        allowDeferredInferredActualTypes: Bool = false
    ) -> Bool {
        if expect.kind == .annotationClass, actual.kind == .typeAlias {
            guard let resolvedType = symbols.typeAliasUnderlyingType(for: actual.id) else {
                return false
            }

            if case let .classType(classType) = types.kind(of: resolvedType) {
                guard classType.nullability == .nonNull,
                      let underlyingSymbol = symbols.symbol(classType.classSymbol)
                else {
                    return false
                }
                return underlyingSymbol.kind == .annotationClass
            }
            return false
        }

        if expect.kind == .class, actual.kind == .typeAlias {
            let expectTypeParameters = types.nominalTypeParameterSymbols(for: expect.id)
            let aliasTypeParameters = symbols.typeAliasTypeParameters(for: actual.id)
            guard let targetClassID = actualTypeAliasTargetClassSymbol(
                for: actual,
                symbols: symbols,
                types: types
            ), let targetClass = symbols.symbol(targetClassID),
                let underlyingType = symbols.typeAliasUnderlyingType(for: actual.id),
                case let .classType(underlyingClassType) = types.kind(of: underlyingType),
                expectTypeParameters.count == aliasTypeParameters.count,
                let immediateTarget = symbols.symbol(underlyingClassType.classSymbol),
                underlyingClassType.args.count == (immediateTarget.kind == .typeAlias
                    ? symbols.typeAliasTypeParameters(for: immediateTarget.id).count
                    : types.nominalTypeParameterSymbols(for: immediateTarget.id).count),
                expect.flags.contains(.valueType) == targetClass.flags.contains(.valueType)
            else {
                return false
            }

            let typeParameterMapping = Dictionary(uniqueKeysWithValues: zip(expectTypeParameters, aliasTypeParameters))
            return expectActualTypeBoundListsMatch(
                expectTypeParameters.map { symbols.typeParameterUpperBounds(for: $0) },
                aliasTypeParameters.map { symbols.typeParameterUpperBounds(for: $0) },
                typeParamMapping: typeParameterMapping,
                symbols: symbols,
                types: types
            )
        }

        switch expect.kind {
        case .function, .constructor:
            guard let expectSig = symbols.functionSignature(for: expect.id),
                  let actualSig = symbols.functionSignature(for: actual.id)
            else {
                return false
            }
            return expectActualFunctionSignaturesMatch(
                expectSig: expectSig,
                expectSymbol: expect,
                actualSig: actualSig,
                actualSymbol: actual,
                symbols: symbols,
                types: types,
                deferActualReturnType: allowDeferredInferredActualTypes
                    && isDeferredInferredActualReturnType(
                        actual,
                        actualSig: actualSig,
                        functionsByRange: sourceDeclarations.functionsByRange,
                        symbols: symbols,
                        types: types
                    )
            )

        case .property, .field:
            guard let expectType = symbols.propertyType(for: expect.id),
                  let actualType = symbols.propertyType(for: actual.id)
            else {
                return false
            }
            let typeParamMapping = makeOwnerTypeParameterMapping(
                expect: expect,
                actual: actual,
                symbols: symbols,
                types: types
            )
            guard expect.flags.contains(.mutable) == actual.flags.contains(.mutable)
                && expectActualOptionalTypeMatch(
                    symbols.extensionPropertyReceiverType(for: expect.id),
                    symbols.extensionPropertyReceiverType(for: actual.id),
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )
            else {
                return false
            }
            if expectActualTypesMatch(
                expectType,
                actualType,
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            ) {
                return true
            }
            // An actual property without a type annotation stores the header's
            // Any? placeholder until body analysis publishes the inferred type.
            return allowDeferredInferredActualTypes
                && isDeferredInferredActualPropertyType(
                    actual,
                    propertiesByRange: sourceDeclarations.propertiesByRange,                    symbols: symbols,
                    types: types
                ))

        case .class, .interface, .object, .enumClass, .annotationClass:
            let expectTPs = types.nominalTypeParameterSymbols(for: expect.id)
            let actualTPs = types.nominalTypeParameterSymbols(for: actual.id)
            guard expectTPs.count == actualTPs.count else { return false }
            let typeParamMapping = Dictionary(uniqueKeysWithValues: zip(expectTPs, actualTPs))
            let expectVariances = types.nominalTypeParameterVariances(for: expect.id)
            let actualVariances = types.nominalTypeParameterVariances(for: actual.id)
            for (index, (eTP, aTP)) in zip(expectTPs, actualTPs).enumerated() {
                let eVar = index < expectVariances.count ? expectVariances[index] : TypeVariance.invariant
                let aVar = index < actualVariances.count ? actualVariances[index] : TypeVariance.invariant
                guard eVar == aVar else { return false }
                guard expectActualTypeListsMatch(
                    symbols.typeParameterUpperBounds(for: eTP),
                    symbols.typeParameterUpperBounds(for: aTP),
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                ) else {
                    return false
                }
            }
            let expectSupertypes = symbols.directSupertypes(for: expect.id)
            let actualSupertypes = symbols.directSupertypes(for: actual.id)
            guard expect.kind == .class || expectSupertypes.count == actualSupertypes.count else {
                return false
            }

            for (index, expectSuper) in expectSupertypes.enumerated() {
                let actualSuper: SymbolID
                if expect.kind == .class {
                    guard let matchingActualSuper = actualSupertypes.first(where: { actualSuper in
                        expectActualNominalSymbolsMatch(expectSuper, actualSuper, symbols: symbols, types: types)
                    }) else {
                        return false
                    }
                    actualSuper = matchingActualSuper
                } else {
                    actualSuper = actualSupertypes[index]
                }

                guard expectActualNominalSymbolsMatch(expectSuper, actualSuper, symbols: symbols, types: types) else {
                    return false
                }
                let expectArgs = types.nominalSupertypeTypeArgs(for: expect.id, supertype: expectSuper)
                let actualArgs = types.nominalSupertypeTypeArgs(for: actual.id, supertype: actualSuper)
                guard expectActualTypeArgsMatch(
                    expectArgs,
                    actualArgs,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                ) else {
                    return false
                }
            }
            return expect.flags.contains(.valueType) == actual.flags.contains(.valueType)

        case .typeAlias:
            let expectTPs = symbols.typeAliasTypeParameters(for: expect.id)
            let actualTPs = symbols.typeAliasTypeParameters(for: actual.id)
            guard expectTPs.count == actualTPs.count else {
                return false
            }
            let typeParamMapping = Dictionary(uniqueKeysWithValues: zip(expectTPs, actualTPs))
            guard expectActualTypeBoundListsMatch(
                expectTPs.map { symbols.typeParameterUpperBounds(for: $0) },
                actualTPs.map { symbols.typeParameterUpperBounds(for: $0) },
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            ) else {
                return false
            }
            guard let expectUnderlying = symbols.typeAliasUnderlyingType(for: expect.id),
                  let actualUnderlying = symbols.typeAliasUnderlyingType(for: actual.id)
            else {
                return false
            }
            return expectActualTypesMatch(
                expectUnderlying,
                actualUnderlying,
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            )

        case .package:
            return true

        case .typeParameter:
            return false

        case .backingField, .valueParameter, .local, .label:
            // These symbol kinds are not meaningful as expect/actual declarations.
            return false
        }
    }

    private func expectActualFunctionSignaturesMatch(
        expectSig: FunctionSignature,
        expectSymbol: SemanticSymbol,
        actualSig: FunctionSignature,
        actualSymbol: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem,
        deferActualReturnType: Bool = false
    ) -> Bool {
        guard expectSig.parameterTypes.count == actualSig.parameterTypes.count,
              expectSig.isSuspend == actualSig.isSuspend,
              expectSig.valueParameterIsVararg == actualSig.valueParameterIsVararg,
              expectSig.reifiedTypeParameterIndices == actualSig.reifiedTypeParameterIndices,
              expectSig.classTypeParameterCount == actualSig.classTypeParameterCount
        else {
            return false
        }

        var typeParamMapping = makeOwnerTypeParameterMapping(
            expect: expectSymbol,
            actual: actualSymbol,
            symbols: symbols,
            types: types
        )

        guard expectSig.typeParameterSymbols.count == actualSig.typeParameterSymbols.count else {
            return false
        }
        for (expectTP, actualTP) in zip(expectSig.typeParameterSymbols, actualSig.typeParameterSymbols) {
            typeParamMapping[expectTP] = actualTP
        }

        guard expectActualOptionalTypeListsMatch(
            expectSig.typeParameterUpperBounds,
            actualSig.typeParameterUpperBounds,
            typeParamMapping: typeParamMapping,
            symbols: symbols,
            types: types
        ), expectActualTypeBoundListsMatch(
            expectSig.typeParameterUpperBoundsList,
            actualSig.typeParameterUpperBoundsList,
            typeParamMapping: typeParamMapping,
            symbols: symbols,
            types: types
        ) else {
            return false
        }

        guard expectActualOptionalTypeMatch(
            expectSig.receiverType,
            actualSig.receiverType,
            typeParamMapping: typeParamMapping,
            symbols: symbols,
            types: types
        ), expectActualTypeListsMatch(
            expectSig.parameterTypes,
            actualSig.parameterTypes,
            typeParamMapping: typeParamMapping,
            symbols: symbols,
            types: types
        ) else {
            return false
        }

        return deferActualReturnType || expectActualTypesMatch(
            expectSig.returnType,
            actualSig.returnType,
            typeParamMapping: typeParamMapping,
            symbols: symbols,
            types: types
        )
    }

    /// True when the matched pair still has a deferred type component — the
    /// actual declaration omitted its type/return-type annotation, so only the
    /// header placeholder was available at match time. The provisional link is
    /// re-verified once body analysis publishes the inferred type.
    private func isDeferredInferredTypePair(
        expect: SemanticSymbol,
        actual: SemanticSymbol,
        sourceDeclarations: ExpectActualSourceDeclarations,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        switch expect.kind {
        case .property, .field:
            return isDeferredInferredActualPropertyType(
                actual,
                propertiesByRange: sourceDeclarations.propertiesByRange,
                symbols: symbols,
                types: types
            )
        case .function, .constructor:
            guard let actualSig = symbols.functionSignature(for: actual.id) else {
                return false
            }
            return isDeferredInferredActualReturnType(
                actual,
                actualSig: actualSig,
                functionsByRange: sourceDeclarations.functionsByRange,
                symbols: symbols,
                types: types
            )
        default:
            return false
        }
    }

    /// An actual property declared without a type annotation is assigned the
    /// `Any?` placeholder during header collection; the real type arrives only
    /// when its initializer or getter is type-checked in body analysis.
    private func isDeferredInferredActualPropertyType(
        _ actual: SemanticSymbol,
        propertiesByRange: [SourceRange: [PropertyDecl]],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard symbols.propertyType(for: actual.id) == types.nullableAnyType,
              let declSite = actual.declSite,
              let declaration = propertiesByRange[declSite]?.first(where: {
                  $0.name == actual.name
              }),
              declaration.type == nil
        else {
            return false
        }
        return true
    }

    /// An expression-bodied actual function without a return-type annotation
    /// stores `Any` in its header signature until `inferFunctionReturnTypes`
    /// publishes the inferred return type during body analysis.
    private func isDeferredInferredActualReturnType(
        _ actual: SemanticSymbol,
        actualSig: FunctionSignature,
        functionsByRange: [SourceRange: [FunDecl]],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard actualSig.returnType == types.anyType,
              let declaration = functionDeclaration(
                  for: actual,
                  in: functionsByRange
              ),
              declaration.returnType == nil,
              case .expr = declaration.body
        else {
            return false
        }
        return true
    }

    private func makeOwnerTypeParameterMapping(
        expect: SemanticSymbol,
        actual: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> [SymbolID: SymbolID] {
        guard let expectOwner = symbols.parentSymbol(for: expect.id),
              let actualOwner = symbols.parentSymbol(for: actual.id),
              expectActualNominalSymbolsMatch(expectOwner, actualOwner, symbols: symbols, types: types)
        else {
            return [:]
        }

        let expectParams = types.nominalTypeParameterSymbols(for: expectOwner)
        let actualParams = types.nominalTypeParameterSymbols(for: actualOwner)
        guard expectParams.count == actualParams.count else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: zip(expectParams, actualParams))
    }

    private func expectActualTypeListsMatch(
        _ expectTypes: [TypeID],
        _ actualTypes: [TypeID],
        typeParamMapping: [SymbolID: SymbolID],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard expectTypes.count == actualTypes.count else {
            return false
        }
        for (expectType, actualType) in zip(expectTypes, actualTypes) {
            guard expectActualTypesMatch(
                expectType,
                actualType,
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            ) else {
                return false
            }
        }
        return true
    }

    private func expectActualTypeBoundListsMatch(
        _ expectBounds: [[TypeID]],
        _ actualBounds: [[TypeID]],
        typeParamMapping: [SymbolID: SymbolID],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard expectBounds.count == actualBounds.count else {
            return false
        }
        for (expectList, actualList) in zip(expectBounds, actualBounds) {
            guard expectActualTypeListsMatch(
                expectList,
                actualList,
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            ) else {
                return false
            }
        }
        return true
    }

    private func expectActualOptionalTypeListsMatch(
        _ expectTypes: [TypeID?],
        _ actualTypes: [TypeID?],
        typeParamMapping: [SymbolID: SymbolID],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard expectTypes.count == actualTypes.count else {
            return false
        }
        for (expectType, actualType) in zip(expectTypes, actualTypes) {
            guard expectActualOptionalTypeMatch(
                expectType,
                actualType,
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            ) else {
                return false
            }
        }
        return true
    }

    private func expectActualOptionalTypeMatch(
        _ expectType: TypeID?,
        _ actualType: TypeID?,
        typeParamMapping: [SymbolID: SymbolID],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        switch (expectType, actualType) {
        case (.none, .none):
            true
        case let (.some(expectType), .some(actualType)):
            expectActualTypesMatch(
                expectType,
                actualType,
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            )
        default:
            false
        }
    }

    private func expectActualTypeArgsMatch(
        _ expectArgs: [TypeArg],
        _ actualArgs: [TypeArg],
        typeParamMapping: [SymbolID: SymbolID],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard expectArgs.count == actualArgs.count else {
            return false
        }

        for (expectArg, actualArg) in zip(expectArgs, actualArgs) {
            switch (expectArg, actualArg) {
            case (.star, .star):
                continue
            case let (.invariant(expectType), .invariant(actualType)),
                 let (.out(expectType), .out(actualType)),
                 let (.in(expectType), .in(actualType)):
                guard expectActualTypesMatch(
                    expectType,
                    actualType,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                ) else {
                    return false
                }
            default:
                return false
            }
        }

        return true
    }

    private func expectActualTypesMatch(
        _ expectType: TypeID,
        _ actualType: TypeID,
        typeParamMapping: [SymbolID: SymbolID],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        switch (types.kind(of: expectType), types.kind(of: actualType)) {
        case (.error, .error), (.unit, .unit), (.nullableUnit, .nullableUnit), (.platformUnit, .platformUnit):
            return true

        case let (.nothing(expectNullability), .nothing(actualNullability)):
            return expectNullability == actualNullability

        case let (.any(expectNullability), .any(actualNullability)):
            return expectNullability == actualNullability

        case let (.stringStruct(expectNullability), .stringStruct(actualNullability)):
            return expectNullability == actualNullability

        case let (.primitive(expectPrimitive, expectNullability), .primitive(actualPrimitive, actualNullability)):
            return expectPrimitive == actualPrimitive && expectNullability == actualNullability

        case let (.typeParam(expectParam), .typeParam(actualParam)):
            let mapped = typeParamMapping[expectParam.symbol] ?? expectParam.symbol
            return mapped == actualParam.symbol && expectParam.nullability == actualParam.nullability

        case let (.classType(expectClass), .classType(actualClass)):
            return expectClass.nullability == actualClass.nullability
                && expectActualNominalSymbolsMatch(
                    expectClass.classSymbol,
                    actualClass.classSymbol,
                    symbols: symbols,
                    types: types
                )
                && expectActualTypeArgsMatch(
                    expectClass.args,
                    actualClass.args,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )

        case let (.functionType(expectFunction), .functionType(actualFunction)):
            return expectFunction.isSuspend == actualFunction.isSuspend
                && expectFunction.nullability == actualFunction.nullability
                && expectActualTypeListsMatch(
                    expectFunction.contextReceivers,
                    actualFunction.contextReceivers,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )
                && expectActualOptionalTypeMatch(
                    expectFunction.receiver,
                    actualFunction.receiver,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )
                && expectActualTypeListsMatch(
                    expectFunction.params,
                    actualFunction.params,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )
                && expectActualTypesMatch(
                    expectFunction.returnType,
                    actualFunction.returnType,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )

        case let (.kClassType(expectKClass), .kClassType(actualKClass)):
            return expectKClass.nullability == actualKClass.nullability
                && expectActualTypesMatch(
                    expectKClass.argument,
                    actualKClass.argument,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )

        case let (.intersection(expectParts), .intersection(actualParts)):
            return expectActualTypeListsMatch(
                expectParts,
                actualParts,
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            )

        default:
            return false
        }
    }

    private func expectActualNominalSymbolsMatch(
        _ expectSymbolID: SymbolID,
        _ actualSymbolID: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard let expectSymbol = symbols.symbol(expectSymbolID),
              let actualSymbol = symbols.symbol(actualSymbolID)
        else {
            return false
        }
        if expectSymbol.kind == actualSymbol.kind && expectSymbol.fqName == actualSymbol.fqName {
            return true
        }
        guard expectSymbol.kind == .class,
              let actualAliasID = symbols.actualSymbol(for: expectSymbolID),
              let actualAlias = symbols.symbol(actualAliasID),
              actualAlias.kind == .typeAlias,
              actualAlias.id == actualSymbolID
                  || actualTypeAliasTargetClassSymbol(for: actualAlias, symbols: symbols, types: types) == actualSymbolID
        else {
            return false
        }
        return true
    }
}
