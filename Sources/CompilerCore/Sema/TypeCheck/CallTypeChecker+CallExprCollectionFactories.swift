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
            let factoryTypeArity: Int? = switch name {
            case "emptyList", "listOf", "listOfNotNull", "mutableListOf", "arrayListOf",
                 "emptySet", "setOf", "setOfNotNull", "mutableSetOf", "hashSetOf", "linkedSetOf":
                1
            case "emptyMap", "mapOf", "mutableMapOf", "hashMapOf", "linkedMapOf":
                2
            default:
                nil
            }
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

            /// The nominal collection type the factory produces for the given
            /// arguments — used only to test whether an expected type is one
            /// the call result can satisfy (`List<Int>` fits `Collection<Int>`
            /// but never `MutableList<Int>` or `Sequence<Int>`).
            func producedFactoryReturnType(elements: [TypeID]) -> TypeID? {
                guard let first = elements.first else { return nil }
                let second = elements.count > 1 ? elements[1] : elements[0]
                switch name {
                case "emptyList", "listOf", "listOfNotNull":
                    return makeSyntheticListType(
                        symbols: sema.symbols, types: sema.types,
                        interner: interner, elementType: first
                    )
                case "mutableListOf":
                    return makeSyntheticMutableListType(
                        symbols: sema.symbols, types: sema.types,
                        interner: interner, elementType: first
                    )
                case "arrayListOf":
                    return makeSyntheticListConstructorType(
                        name: "ArrayList", symbols: sema.symbols, types: sema.types,
                        interner: interner, elementType: first
                    )
                case "emptySet", "setOf", "setOfNotNull":
                    return makeSyntheticSetType(
                        symbols: sema.symbols, types: sema.types,
                        interner: interner, elementType: first
                    )
                case "mutableSetOf":
                    return makeSyntheticMutableSetType(
                        symbols: sema.symbols, types: sema.types,
                        interner: interner, elementType: first
                    )
                case "hashSetOf":
                    return makeSyntheticHashSetType(
                        symbols: sema.symbols, types: sema.types,
                        interner: interner, elementType: first
                    )
                case "linkedSetOf":
                    return makeSyntheticLinkedHashSetType(
                        symbols: sema.symbols, types: sema.types,
                        interner: interner, elementType: first
                    )
                case "emptyMap", "mapOf":
                    return makeSyntheticMapType(
                        symbols: sema.symbols, types: sema.types,
                        interner: interner, keyType: first, valueType: second
                    )
                case "mutableMapOf":
                    return makeSyntheticMutableMapType(
                        symbols: sema.symbols, types: sema.types,
                        interner: interner, keyType: first, valueType: second
                    )
                case "hashMapOf":
                    return makeSourceBackedHashMapType(
                        symbols: sema.symbols, types: sema.types,
                        interner: interner, keyType: first, valueType: second
                    )
                case "linkedMapOf":
                    return makeSourceBackedLinkedHashMapType(
                        symbols: sema.symbols, types: sema.types,
                        interner: interner, keyType: first, valueType: second
                    )
                default:
                    return nil
                }
            }

            /// Whether the expected type supplies a concrete argument for
            /// every type parameter the factory still needs — the way
            /// `List<Int>` or `Collection<Int>` pins T while `List<*>`,
            /// `Collection<*>`, `Any` and `Any?` do not, and `Map<String, *>`
            /// pins K but not V. The produced nominal must also fit:
            /// `MutableList<Int>` pins the element of `mutableListOf` but not
            /// of `listOf` (KUU-4002).
            func expectedTypeProvidesConcreteElementTypes(arity: Int) -> Bool {
                guard let expected = expectedCollectionType(withArity: arity),
                      case let .classType(expectedClass) = sema.types.kind(of: expected)
                else { return false }
                var elements: [TypeID] = []
                for argument in expectedClass.args.prefix(arity) {
                    let element: TypeID
                    switch argument {
                    case let .invariant(type), let .out(type), let .in(type):
                        element = type
                    case .star:
                        return false
                    }
                    // A star-captured argument is not proper evidence either:
                    // `T <: Captured` cannot fix a type variable in kotlinc.
                    if case let .typeParam(parameter) = sema.types.kind(of: element),
                       parameter.capture != nil
                    {
                        return false
                    }
                    elements.append(element)
                }
                guard let produced = producedFactoryReturnType(elements: elements) else {
                    return false
                }
                // The produced nominal must relate to the target either way:
                // `List<Int>` fits `Collection<Int>` upward, and a narrower
                // `HashMap<K, V>` can adopt the produced `MutableMap<K, V>`
                // the way bundled `hashMapOf` relies on. `Set<Int>` never
                // pins `listOf`/`emptyList` in either direction.
                return sema.types.isSubtype(produced, expected)
                    || sema.types.isSubtype(expected, produced)
            }

            if ctx.collectionFactoryInferenceRequiredForEqualityOperand == id,
               args.isEmpty, explicitTypeArgs.isEmpty,
               let factoryTypeArity,
               expectedCollectionType(withArity: factoryTypeArity) == nil
            {
                return nil
            }

            // A bare `listOf()`/`emptyList()`/`setOf()`/`mapOf()`-family call
            // supplies no argument or explicit-type-argument evidence, so the
            // expected type is the only remaining source of inference.
            // kotlinc rejects the call when that type cannot pin every factory
            // type parameter ("cannot infer type for type parameter 'T'"),
            // so report the same inference failure. An argument position whose
            // candidates never produced a usable expected type still keeps the
            // Nothing-shaped result silently: the enclosing call's chosen
            // parameter can pin the factory through joint inference the way
            // `this(emptyList())`, `xs.addAll(emptyList())`, or
            // `list + emptyList()` require (KUU-4002).
            /// An argument position only defers when the propagated expected
            /// type offers no concrete evidence at all: either none was
            /// computed, or every argument position is still a bare type
            /// parameter the enclosing call binds elsewhere —
            /// `xs.addAll(emptyList())` sees `Collection<E>` while the
            /// `MutableList<Int>` receiver supplies `E` (KUU-4002). A star
            /// projection is an explicit *absence* of evidence, not a hole
            /// the call will fill, so `Collection<*>` still reports.
            let suppressesUninferredArgument: Bool = {
                guard ctx.callArgumentExprBeingInferred == id else { return false }
                guard let expectedType, expectedType != sema.types.errorType else {
                    return true
                }
                guard case let .classType(expectedClass) = sema.types.kind(of: expectedType),
                      !expectedClass.args.isEmpty
                else {
                    return false
                }
                return expectedClass.args.allSatisfy { argument in
                    switch argument {
                    case let .invariant(inner), let .out(inner), let .in(inner):
                        if case .typeParam = sema.types.kind(of: inner) { return true }
                        return false
                    case .star:
                        return false
                    }
                }
            }()
            if args.isEmpty, explicitTypeArgs.isEmpty,
               let arity = factoryTypeArity,
               !expectedTypeProvidesConcreteElementTypes(arity: arity),
               !suppressesUninferredArgument,
               let callRange = ctx.ast.arena.exprRange(id)
            {
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-INFER",
                    "Cannot infer type argument from the call arguments and expected type; provide explicit type arguments or an explicit expected type.",
                    range: callRange
                )
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
                let explicitElementType = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs)
                // Kotlin infers a generic collection's element type from a
                // non-literal input and then widens compatible integer constant
                // expressions to that type — `mutableListOf(1, 1L)` is a
                // MutableList<Long>. Keep the constants out of the ordinary
                // LUB the way the set factories below already do, then bind
                // the literals to that element type before lowering reads
                // their types (KUU-3789; mirrors the setOf fix).
                let integerConstantArguments = args.indices.filter { index in
                    guard !args[index].isSpread else { return false }
                    let literal = integerLiteralValues(args[index].expr, ast: ctx.ast)
                    return literal.signed != nil || literal.unsigned != nil
                }
                let nonLiteralElementTypes = zip(args, argTypes).compactMap { argument, type -> TypeID? in
                    guard !argument.isSpread else { return nil }
                    let literal = integerLiteralValues(argument.expr, ast: ctx.ast)
                    guard literal.signed == nil, literal.unsigned == nil else { return nil }
                    if name == "listOfNotNull", type == sema.types.nullableNothingType {
                        return nil
                    }
                    return name == "listOfNotNull" ? sema.types.makeNonNullable(type) : type
                }
                let contextualIntegerType = explicitElementType
                    ?? (nonLiteralElementTypes.isEmpty ? nil : sema.types.lub(nonLiteralElementTypes))
                let canContextualizeIntegerConstants = !args.contains(where: \.isSpread)
                    && !integerConstantArguments.isEmpty
                    && contextualIntegerType.map { targetType in
                        integerConstantArguments.allSatisfy { index in
                            integerLiteralFitsParameter(args[index].expr, parameterType: targetType, ctx: ctx)
                        }
                    } == true
                let fallbackElementType = elementTypes.isEmpty
                    ? contextualElementType ?? sema.types.nothingType
                    : sema.types.lub(elementTypes)
                let inferredElementType = canContextualizeIntegerConstants
                    ? contextualIntegerType ?? fallbackElementType
                    : fallbackElementType

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
                func collectionType(elementType: TypeID) -> TypeID {
                    if name == "linkedSetOf" {
                        makeSyntheticLinkedHashSetType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    } else if name == "hashSetOf" {
                        makeSyntheticHashSetType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    } else if name == "mutableSetOf" {
                        makeSyntheticMutableSetType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    } else {
                        makeSyntheticSetType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    }
                }
                if let expectedType, explicitTypeArgs.isEmpty {
                    let expectedElementType = typeArgs(from: expectedType).first
                    if let expectedElementType,
                       sema.types.isSubtype(collectionType(elementType: expectedElementType), expectedType)
                    {
                        return (expectedType, typeArgs(from: expectedType))
                    }
                }
                let elementTypes = name == "setOfNotNull"
                    ? argTypes.compactMap { type -> TypeID? in
                        type == sema.types.nullableNothingType ? nil : sema.types.makeNonNullable(type)
                    }
                    : argTypes
                let explicitElementType = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs)
                let integerConstantArguments = args.indices.filter { index in
                    guard !args[index].isSpread else { return false }
                    let literal = integerLiteralValues(args[index].expr, ast: ctx.ast)
                    return literal.signed != nil || literal.unsigned != nil
                }
                let nonLiteralElementTypes = zip(args, argTypes).compactMap { argument, type -> TypeID? in
                    guard !argument.isSpread else { return nil }
                    let literal = integerLiteralValues(argument.expr, ast: ctx.ast)
                    guard literal.signed == nil, literal.unsigned == nil else { return nil }
                    if name == "setOfNotNull", type == sema.types.nullableNothingType {
                        return nil
                    }
                    return name == "setOfNotNull" ? sema.types.makeNonNullable(type) : type
                }
                let contextualIntegerType = explicitElementType
                    ?? (nonLiteralElementTypes.isEmpty ? nil : sema.types.lub(nonLiteralElementTypes))
                // Kotlin can infer a generic collection's element type from a
                // non-literal input and then widen compatible integer constant
                // expressions to that type. Keep those constants out of the
                // ordinary LUB so setOf(1, 1L) becomes Set<Long>, then bind the
                // literals to Long below before lowering reads their types.
                let canContextualizeIntegerConstants = !args.contains(where: \.isSpread)
                    && !integerConstantArguments.isEmpty
                    && contextualIntegerType.map { targetType in
                        integerConstantArguments.allSatisfy { index in
                            integerLiteralFitsParameter(args[index].expr, parameterType: targetType, ctx: ctx)
                        }
                    } == true
                let fallbackElementType = elementTypes.isEmpty
                    ? sema.types.nothingType : sema.types.lub(elementTypes)
                let inferredElementType = canContextualizeIntegerConstants
                    ? contextualIntegerType ?? fallbackElementType
                    : fallbackElementType
                let elementType = explicitElementType ?? inferredElementType
                return (collectionType(elementType: elementType), [elementType])

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
                       // source shape. A single ordinary argument selects the
                       // fixed overload; spreads and all other arities use the
                       // vararg overload and its packing contract.
                       let isVararg = sema.symbols.functionSignature(for: candidate)?
                           .valueParameterIsVararg.first ?? false
                       return isVararg == (args.count != 1 || args.contains(where: \.isSpread))
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
                // KUU-3789: the same integer-literal rebinding the set
                // factories already get. `mutableListOf<Long>(1)` resolves
                // T=Long only for the result type here; without re-inferring
                // the literal against that element type it stays Int, the
                // lowering boxes it with kk_box_int, and a later Long unbox
                // reads the wrong box.
                if ["emptyList", "listOf", "listOfNotNull", "mutableListOf", "arrayListOf",
                    "emptySet", "setOf", "setOfNotNull", "mutableSetOf", "hashSetOf", "linkedSetOf"]
                    .contains(resolvedName),
                   let elementType = sourceBackedFactory.typeArgs.first
                {
                    var contextualizedLocals = locals
                    for argument in args where !argument.isSpread {
                        let literal = integerLiteralValues(argument.expr, ast: ctx.ast)
                        guard literal.signed != nil || literal.unsigned != nil,
                              integerLiteralFitsParameter(argument.expr, parameterType: elementType, ctx: ctx)
                        else { continue }
                        _ = driver.inferExpr(
                            argument.expr,
                            ctx: ctx,
                            locals: &contextualizedLocals,
                            expectedType: elementType
                        )
                    }
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
