// swiftlint:disable file_length function_body_length cyclomatic_complexity

/// Source-backed collection-factory binding for `inferCallExpr`: selects
/// the bundled `listOf`/`setOf`/`mapOf`-family declaration for a call and
/// derives its result type from the inferred argument types.
/// Extracted from `CallTypeChecker+CallExprInference.swift`.
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
                return expectedType
            }

            switch name {
            case "emptyList", "listOf", "listOfNotNull", "mutableListOf", "arrayListOf":
                if let expectedType = expectedCollectionType(withArity: 1) {
                    return (expectedType, typeArgs(from: expectedType))
                }
                let elementTypes = name == "listOfNotNull"
                    ? argTypes.compactMap { type -> TypeID? in
                        type == sema.types.nullableNothingType ? nil : sema.types.makeNonNullable(type)
                    }
                    : argTypes
                let elementType = explicitTypeArgs.first
                    ?? (elementTypes.isEmpty ? sema.types.nothingType : sema.types.lub(elementTypes))
                let resultType: TypeID
                if name == "arrayListOf" {
                    resultType = makeSyntheticListConstructorType(
                        name: "ArrayList",
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                } else if name == "mutableListOf" {
                    resultType = makeSyntheticMutableListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                } else {
                    resultType = makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                }
                return (resultType, [elementType])

            case "emptySet", "setOf", "setOfNotNull", "mutableSetOf", "hashSetOf", "linkedSetOf":
                if let expectedType = expectedCollectionType(withArity: 1) {
                    return (expectedType, typeArgs(from: expectedType))
                }
                let elementTypes = name == "setOfNotNull"
                    ? argTypes.compactMap { type -> TypeID? in
                        type == sema.types.nullableNothingType ? nil : sema.types.makeNonNullable(type)
                    }
                    : argTypes
                let elementType = explicitTypeArgs.first
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
                if let expectedType = expectedCollectionType(withArity: 2) {
                    return (expectedType, typeArgs(from: expectedType))
                }
                // Spread arguments contribute their array element (Pair<K, V>),
                // not the array itself, to the factory's key/value inference.
                let pairTypes = zip(args, argTypes).map { argument, type in
                    argument.isSpread
                        ? (driver.helpers.arrayElementType(for: type, sema: sema, interner: interner)
                            ?? sema.types.errorType)
                        : type
                }
                let keyType: TypeID
                let valueType: TypeID
                if explicitTypeArgs.count == 2 {
                    keyType = explicitTypeArgs[0]
                    valueType = explicitTypeArgs[1]
                } else if let inferred = inferSyntheticMapKeyValueTypes(from: pairTypes, ctx: ctx) {
                    keyType = inferred.keyType
                    valueType = inferred.valueType
                } else {
                    keyType = sema.types.nothingType
                    valueType = sema.types.nothingType
                }
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
            // mapOf has both fixed-arity and vararg source declarations. Let the
            // regular resolver distinguish them for non-empty calls instead of
            // binding the first collection-factory candidate unconditionally.
            if !(resolvedName == "mapOf" && !args.isEmpty),
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

            // The collection aliases and the concrete LinkedHashSet class are
            // type declarations (Stdlib/kotlin/collections/CollectionAliases.kt)
            // rather than factory functions, so their constructor calls are typed
            // here; CollectionLiteralLoweringPass rewrites the resulting calls to
            // the matching runtime bridge.
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
            let constructorElementType = explicitTypeArgs.first
                ?? expectedCollectionArgs.first
                ?? (resolvedName == "HashSet" ? argTypes.first.flatMap { argumentType in
                    guard case let .classType(argumentClassType) = sema.types.kind(
                        of: sema.types.makeNonNullable(argumentType)
                    ),
                    let firstArgument = argumentClassType.args.first
                    else {
                        return nil
                    }
                    return switch firstArgument {
                    case let .invariant(type), let .in(type), let .out(type): type
                    case .star: sema.types.anyType
                    }
                } : nil)
                ?? sema.types.anyType
            switch resolvedName {
            case "ArrayList":
                let arrayListElementType: TypeID = if let explicit = explicitTypeArgs.first {
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
                let keyType = explicitTypeArgs.first
                    ?? expectedCollectionArgs.first
                    ?? inferredMapTypes?.keyType
                    ?? sema.types.anyType
                let valueType = explicitTypeArgs.dropFirst().first
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
