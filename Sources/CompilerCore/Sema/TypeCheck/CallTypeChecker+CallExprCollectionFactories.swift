// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func inferSourceBackedCollectionFactoryCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        candidates: [SymbolID],
        argTypes: [TypeID]
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        func sourceBackedCollectionFactoryType(
            name: String
        ) -> (type: TypeID, typeArgs: [TypeID])? {
            func typeArgs(from type: TypeID) -> [TypeID] {
                guard case let .classType(classType) = sema.types.kind(of: type) else {
                    return []
                }
                return classType.args.map { arg in
                    switch arg {
                    case let .invariant(type), let .in(type), let .out(type):
                        type
                    case .star:
                        sema.types.anyType
                    }
                }
            }

            func expectedCollectionType(withArity arity: Int) -> TypeID? {
                guard let expectedType,
                      expectedType != sema.types.errorType,
                      case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                      expectedClassType.args.count >= arity
                else {
                    return nil
                }
                // Collection factories are non-null even when their contextual
                // assignment target is nullable. Keep the target's type arguments
                // without propagating its nullability to the call result.
                return sema.types.makeNonNullable(expectedType)
            }

            func isMutableCollection(_ type: TypeID) -> Bool {
                guard case let .classType(classType) = sema.types.kind(of: type),
                      let symbol = sema.symbols.symbol(classType.classSymbol)
                else {
                    return false
                }
                let symName = interner.resolve(symbol.name)
                return symName.hasPrefix("Mutable")
                    || symName == "ArrayList"
                    || symName == "HashSet"
                    || symName == "LinkedHashSet"
                    || symName == "HashMap"
                    || symName == "LinkedHashMap"
            }

            switch name {
            case "emptyList", "listOf", "listOfNotNull", "mutableListOf", "arrayListOf":
                let expectedType = expectedCollectionType(withArity: 1)
                if let expectedType, explicitTypeArgs.isEmpty {
                    let isImmutable = name == "emptyList" || name == "listOf" || name == "listOfNotNull"
                    // Mutable factories retain their concrete collection type;
                    // only immutable factories adopt a compatible read-only target.
                    if isImmutable && !isMutableCollection(expectedType) {
                        return (expectedType, typeArgs(from: expectedType))
                    }
                }
                let elementTypes = name == "listOfNotNull"
                    ? zip(args, argTypes).compactMap { argument, type -> TypeID? in
                        let elementType = argument.isSpread
                            ? driver.helpers.arrayElementType(for: type, sema: sema, interner: interner)
                            : type
                        guard let elementType else { return nil }
                        return elementType == sema.types.nullableNothingType
                            ? nil : sema.types.makeNonNullable(elementType)
                    }
                    : zip(args, argTypes).compactMap { argument, type in
                        argument.isSpread
                            ? driver.helpers.arrayElementType(for: type, sema: sema, interner: interner)
                            : type
                    }
                let contextualElementType = expectedType.flatMap { typeArgs(from: $0).first }
                let inferredElementType = elementTypes.isEmpty
                    ? contextualElementType ?? sema.types.nothingType
                    : sema.types.lub(elementTypes)
                let explicitElementType = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs)

                func collectionType(elementType: TypeID) -> TypeID {
                    if name == "arrayListOf" {
                        makeSyntheticListConstructorType(
                            name: "ArrayList",
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    } else if name == "mutableListOf" {
                        makeSyntheticMutableListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    } else {
                        makeSyntheticListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    }
                }

                var elementType = explicitElementType ?? inferredElementType
                var resultType = collectionType(elementType: elementType)
                // Keep the narrow lub-based type when it already fits the target:
                // an explicit backing field initializer is checked against the
                // wider public property type but must stay as narrow as its
                // arguments. For an invariant target such as
                // `val xs: MutableList<Number> = mutableListOf(1)` the lub (Int)
                // does not fit, so fall back to the target's element type.
                if explicitElementType == nil, !elementTypes.isEmpty,
                   let expectedType, let contextualElementType,
                   !sema.types.isSubtype(resultType, expectedType),
                   elementTypes.allSatisfy({ sema.types.isSubtype($0, contextualElementType) })
                {
                    let contextualResultType = collectionType(elementType: contextualElementType)
                    if sema.types.isSubtype(contextualResultType, expectedType) {
                        elementType = contextualElementType
                        resultType = contextualResultType
                    }
                }
                return (resultType, [elementType])

            case "emptySet", "setOf", "setOfNotNull", "mutableSetOf", "hashSetOf", "linkedSetOf":
                let expectedType = expectedCollectionType(withArity: 1)
                if let expectedType, explicitTypeArgs.isEmpty {
                    let isImmutable = name == "emptySet" || name == "setOf" || name == "setOfNotNull"
                    if !(isImmutable && isMutableCollection(expectedType)) {
                        return (expectedType, typeArgs(from: expectedType))
                    }
                }
                let elementTypes = name == "setOfNotNull"
                    ? argTypes.compactMap { type -> TypeID? in
                        type == sema.types.nullableNothingType ? nil : sema.types.makeNonNullable(type)
                    }
                    : argTypes
                let elementType = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs)
                    ?? (elementTypes.isEmpty ? sema.types.nothingType : sema.types.lub(elementTypes))
                let resultType: TypeID
                if name == "linkedSetOf" {
                    resultType = makeSyntheticLinkedHashSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                } else if name == "hashSetOf" {
                    resultType = makeSyntheticHashSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                } else if name == "mutableSetOf" {
                    resultType = makeSyntheticMutableSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                } else {
                    resultType = makeSyntheticSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                }
                return (resultType, [elementType])

            case "emptyMap", "mapOf", "mutableMapOf", "hashMapOf", "linkedMapOf":
                let expectedType = expectedCollectionType(withArity: 2)
                if let expectedType, explicitTypeArgs.isEmpty {
                    let isImmutable = name == "emptyMap" || name == "mapOf"
                    if !(isImmutable && isMutableCollection(expectedType)) {
                        return (expectedType, typeArgs(from: expectedType))
                    }
                }
                // Spread arguments contribute their array element (Pair<K, V>),
                // not the array itself, to the factory's key/value inference.
                let pairTypes = zip(args, argTypes).map { argument, type in
                    argument.isSpread
                        ? (driver.helpers.arrayElementType(for: type, sema: sema, interner: interner)
                            ?? sema.types.errorType)
                        : type
                }
                let inferred = inferSyntheticMapKeyValueTypes(from: pairTypes, ctx: ctx)
                let keyType = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs)
                    ?? inferred?.keyType
                    ?? sema.types.nothingType
                let valueType = resolvedExplicitTypeArgument(at: 1, in: explicitTypeArgs)
                    ?? inferred?.valueType
                    ?? sema.types.nothingType
                let resultType: TypeID
                if name == "mapOf" || name == "emptyMap" {
                    resultType = makeSyntheticMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: keyType,
                        valueType: valueType
                    )
                } else if name == "linkedMapOf" {
                    // KUU-556: linkedMapOf() is declared to return LinkedHashMap<K,
                    // V> (linked.kt), now a real HashMap subclass -- give call
                    // sites that same nominal type instead of the generic
                    // MutableMap hashMapOf/mutableMapOf still get, matching how
                    // linkedSetOf already gets makeSyntheticLinkedHashSetType above.
                    resultType = makeSourceBackedLinkedHashMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: keyType,
                        valueType: valueType
                    )
                } else {
                    resultType = makeSyntheticMutableMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: keyType,
                        valueType: valueType
                    )
                }
                return (resultType, [keyType, valueType])

            default:
                return nil
            }
        }

        func isKotlinCollectionsFactorySymbol(_ symbol: SemanticSymbol, named name: InternedString) -> Bool {
            guard symbol.kind == .function,
                  symbol.name == name,
                  symbol.fqName.count >= 3
            else {
                return false
            }
            return symbol.fqName[0] == knownNames.kotlin
                && symbol.fqName[1] == knownNames.collections
        }

        func hasNonStdlibCollectionFactoryShadow(
            _ name: InternedString,
            locals: LocalBindings,
            ctx: TypeInferenceContext
        ) -> Bool {
            if locals[name] != nil {
                return true
            }
            return ctx.cachedScopeLookup(name).contains { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      !symbol.flags.contains(.synthetic)
                else {
                    return false
                }
                return !isKotlinCollectionsFactorySymbol(symbol, named: name)
            }
        }

        if let calleeName {
            let resolvedName = interner.resolve(calleeName)
            // listOf must use the declaration's argument and result constraints,
            // including explicit type arguments and spread arrays. Assigning the
            // expected result directly would accept List<String> = listOf(1).
            // mapOf also needs regular resolution to select its fixed/vararg
            // overloads for non-empty calls.
            // JVM factories retain their declared overload, vararg, and type constraints.
            if !sema.requiresResolvedLibraryCalls, !(resolvedName == "listOf" && !args.isEmpty), !(resolvedName == "mapOf" && !args.isEmpty),
               let sourceBackedFactory = sourceBackedCollectionFactoryType(name: resolvedName),
               !hasNonStdlibCollectionFactoryShadow(calleeName, locals: locals, ctx: ctx),
               let chosen = candidates.first(where: { candidate in
                   guard let symbol = ctx.cachedSymbol(candidate),
                         isKotlinCollectionsFactorySymbol(symbol, named: calleeName)
                   else {
                       return false
                   }
                   if resolvedName == "listOfNotNull" {
                       // The fixed-arity and vararg overloads share the same
                       // source shape. Select the fixed overload for one
                       // argument and the vararg overload for zero or multiple
                       // arguments so lowering receives the correct packing
                       // contract.
                       let isVararg = sema.symbols.functionSignature(for: candidate)?
                           .valueParameterIsVararg.first ?? false
                       return isVararg == (args.count != 1)
                   }
                   return args.isEmpty || (sema.symbols.functionSignature(for: candidate)?.parameterTypes.isEmpty == false)
               })
            {
                // A superclass hint can contextualize listOf(1) as List<String>.
                // Check actual inputs before the fast path adopts that type;
                // incompatible inputs must go through ordinary diagnostics and
                // allow the enclosing speculative hint to be discarded.
                if ctx.validatesLiftedHintCollectionArguments, expectedType != nil, !args.isEmpty {
                    let callArgs = zip(args, argTypes).map { argument, type in
                        let literal = integerLiteralValues(argument.expr, ast: ctx.ast)
                        return CallArg(
                            label: argument.label, isSpread: argument.isSpread, type: type,
                            signedIntegerLiteral: literal.signed, unsignedIntegerLiteral: literal.unsigned,
                            isTrailingLambda: argument.isTrailingLambda
                        )
                    }
                    guard let range = ctx.ast.arena.exprRange(id),
                          !ctx.resolver.probeCall(
                              candidates: [chosen],
                              call: CallExpr(
                                  range: range, calleeName: calleeName, args: callArgs,
                                  explicitTypeArgs: explicitTypeArgs
                              ),
                              expectedType: expectedType, ctx: sema
                          ).viableCandidates.isEmpty
                    else { return nil }
                }
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: sourceBackedFactory.typeArgs,
                        parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, 0) })
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: sourceBackedFactory.type)
                return sourceBackedFactory.type
            }

            guard ["ArrayList", "HashSet", "LinkedHashSet", "HashMap", "LinkedHashMap"].contains(resolvedName) else {
                return nil
            }
            // The collection aliases and the concrete LinkedHashSet class are
            // type declarations (Stdlib/kotlin/collections/CollectionAliases.kt)
            // rather than factory functions, so their constructor calls are typed
            // here; CollectionLiteralLoweringPass rewrites the resulting calls to
            // the matching runtime bridge.
            // A same-named user declaration must go through ordinary overload
            // resolution rather than acquire a stdlib collection result type.
            let collectionFQName = [knownNames.kotlin, knownNames.collections, calleeName]
            let hasNonStdlibClassifier = ctx.scope.lookupClassifier(calleeName, matching: { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                switch symbol.kind {
                case .class, .interface, .enumClass, .annotationClass, .object, .typeAlias: return true
                default: return false
                }
            }).contains { ctx.cachedSymbol($0)?.fqName != collectionFQName }
            if locals[calleeName] != nil || hasNonStdlibClassifier || candidates.contains(where: { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                let declarationFQName = symbol.kind == .constructor
                    ? Array(symbol.fqName.dropLast()) : symbol.fqName
                return declarationFQName != collectionFQName
            }) {
                return nil
            }
            let expectedCollectionArgs: [TypeID] = if let expectedType,
                                                       expectedType != sema.types.errorType,
                                                       case let .classType(expectedClassType) = sema.types.kind(of: expectedType)
            {
                expectedClassType.args.map { arg in
                    switch arg {
                    case let .invariant(type), let .in(type), let .out(type): type
                    case .star: sema.types.anyType
                    }
                }
            } else {
                []
            }
            let constructorElementType = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs)
                ?? expectedCollectionArgs.first
                ?? (["HashSet", "LinkedHashSet"].contains(resolvedName) ? argTypes.first.flatMap { argumentType in
                    guard case let .classType(argumentClassType) = sema.types.kind(
                        of: sema.types.makeNonNullable(argumentType)
                    ) else { return nil }
                    let elementArgument: TypeArg?
                    if resolvedName == "LinkedHashSet" {
                        // Copy construction must retain the Collection element
                        // even when an enclosing generic call supplies no hint.
                        guard argTypes.count == 1,
                              let collection = sema.symbols.lookup(fqName: [
                                knownNames.kotlin, knownNames.collections, interner.intern("Collection")
                              ]) else { return nil }
                        elementArgument = sema.types.liftedNominalSupertypeArgs(
                            from: argumentClassType.classSymbol, childArgs: argumentClassType.args, to: collection
                        )?.first
                    } else {
                        elementArgument = argumentClassType.args.first
                    }
                    guard let firstArgument = elementArgument else { return nil }
                    return switch firstArgument {
                    case let .invariant(type), let .in(type), let .out(type): type
                    case .star: sema.types.anyType
                    }
                } : nil)
                ?? sema.types.anyType
            switch resolvedName {
            case "ArrayList":
                let arrayListElementType: TypeID = if let explicit = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs) {
                    explicit
                } else if let expected = expectedCollectionArgs.first {
                    expected
                } else if argTypes.count == 1,
                          let argumentType = argTypes.first,
                          case let .classType(argumentClassType) = sema.types.kind(of: argumentType),
                          let argumentElementType = argumentClassType.args.first
                {
                    switch argumentElementType {
                    case let .invariant(type), let .in(type), let .out(type): type
                    case .star: sema.types.anyType
                    }
                } else {
                    constructorElementType
                }
                let resultType = makeSyntheticListConstructorType(
                    name: resolvedName,
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: arrayListElementType
                )
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            case "HashSet":
                let resultType = makeSyntheticHashSetType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: constructorElementType
                )
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            case "LinkedHashSet":
                let resultType = makeSyntheticLinkedHashSetType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: constructorElementType
                )
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            case "HashMap", "LinkedHashMap":
                let inferredMapTypes = inferMapTypeArgumentsFromConstructorArgument(from: argTypes, ctx: ctx)
                let keyType = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs)
                    ?? expectedCollectionArgs.first
                    ?? inferredMapTypes?.keyType
                    ?? sema.types.anyType
                let valueType = resolvedExplicitTypeArgument(at: 1, in: explicitTypeArgs)
                    ?? expectedCollectionArgs.dropFirst().first
                    ?? inferredMapTypes?.valueType
                    ?? sema.types.anyType
                let resultType = resolvedName == "HashMap"
                    ? makeSourceBackedHashMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: keyType,
                        valueType: valueType
                    )
                    : makeSourceBackedLinkedHashMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: keyType,
                        valueType: valueType
                    )
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            default:
                break
            }
        }
        return nil
    }
}
