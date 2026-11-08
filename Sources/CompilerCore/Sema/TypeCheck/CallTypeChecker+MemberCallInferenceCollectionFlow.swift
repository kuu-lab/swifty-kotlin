// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func tryInferMemberCallCollectionFlowSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let expectedType = request.expectedType
        let explicitTypeArgs = request.explicitTypeArgs
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        // `recv.name` without parentheses is property-access syntax: it can
        // only bind a property (or accessor), never one of the collection
        // functions this fast path models. A same-named extension property
        // must win over `first()`/`last()`/`count()` here, and when no
        // property applies regular resolution still binds the function so
        // enforceFunctionInvocationSyntax reports SEMA-0309 (KUU-4387).
        if args.isEmpty, !ast.arena.isExplicitCall(id) {
            return nil
        }
        // Primitive-array source members are bundled Kotlin extensions, not collection or
        // sequence operations. Unsigned arrays currently also classify as
        // synthetic sequences, so let exact primitive-array source lookup run
        // before the generic collection-flow fast path.
        if !collectPrimitiveArraySourceMembers(
            named: calleeName,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ).isEmpty {
            return nil
        }
        if !collectArraySourceBackedCandidates(
            named: calleeName,
            receiverType: receiverType,
            ctx: ctx,
            sema: sema,
            interner: interner
        ).isEmpty {
            return nil
        }
        // Fallback for receivers that were never routed through a `flow { }`/operator
        // call (e.g. a user function declared `fun f(): Flow<Int>`), so the
        // `isFlowExpr`/`isFlowSymbol` bindings were never marked. Recover the
        // same information directly from the receiver's inferred class type.
        let flowClassSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlinx"), interner.intern("coroutines"),
            interner.intern("flow"), interner.intern("Flow"),
        ])
        let receiverFlowClassType: ClassType? = if let flowClassSymbol,
                                                    case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                                                    classType.classSymbol == flowClassSymbol
        {
            classType
        } else {
            nil
        }
        let isFlowReceiver = if sema.bindings.isFlowExpr(receiverID) {
            true
        } else if case .nameRef = ast.arena.expr(receiverID),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
                  sema.bindings.isFlowSymbol(receiverSymbol)
        {
            true
        } else if receiverFlowClassType != nil {
            true
        } else {
            false
        }
        if isFlowReceiver, calleeName == interner.intern("collect") {
            let flowPackage = [interner.intern("kotlinx"), interner.intern("coroutines"), interner.intern("flow")]
            if sema.bundledIndex.contains(
                ownerFQName: flowPackage + [interner.intern("Flow")], name: calleeName, arity: args.count
            ) || sema.symbols.lookupAll(fqName: flowPackage + [calleeName]).contains(where: {
                sema.symbols.isSourceBackedSymbol($0)
            }) {
                return nil
            }
        }
        // Prefer the instantiated receiver type when it is available. Flow
        // expressions can retain the builder's generic element variable in
        // flowElementType even after an explicit call type argument (for
        // example flowOf<Int>(...)) has fixed the public receiver to Flow<Int>.
        let flowElementType: TypeID = if let firstArg = receiverFlowClassType?.args.first {
            switch firstArg {
            case let .invariant(t), let .out(t), let .in(t):
                t
            case .star:
                sema.types.anyType
            }
        } else if let elementType = sema.bindings.flowElementType(forExpr: receiverID) {
            elementType
        } else if case .nameRef = ast.arena.expr(receiverID),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
                  let elementType = sema.bindings.flowElementType(forSymbol: receiverSymbol)
        {
            elementType
        } else {
            sema.types.anyType
        }
        let isFlowHOF = isFlowReceiver && knownNames.flowHOFNames.contains(calleeName)
        let receiverClassifier = ReceiverClassifier(sema: sema, interner: interner)
        let receiverClassification = receiverClassifier.classify(
            receiverID: receiverID,
            receiverType: receiverType,
            ast: ast
        )
        let isCollectionReceiver = receiverClassification.isCollectionReceiver
        let isIterableReceiver = receiverClassification.isIterableReceiver
        let isArrayReceiver = receiverClassification.isArrayReceiver
        let isMapReceiver = receiverClassification.isMapReceiver
        let isMutableListReceiver = receiverClassification.isMutableListReceiver
        let isListReceiver = receiverClassification.isListReceiver
        let isListFactoryReceiver = receiverClassification.isListFactoryReceiver
        let isSyntheticSequenceReceiver = receiverClassification.isSyntheticSequenceReceiver
        let isSequenceReceiver = receiverClassification.isSequenceReceiver
        let isSetReceiver = receiverClassification.isSetReceiver
        let isEnumEntriesReceiver: Bool = {
            guard let (_, symbol) = resolveClassTypeSymbol(
                sema.types.makeNonNullable(receiverType),
                sema: sema
            ) else {
                return false
            }
            return symbol.fqName == knownNames.kotlinEnumsEnumEntriesFQName
        }()
        let isStringReceiver = sema.types.isSubtype(
            sema.types.makeNonNullable(receiverType),
            sema.types.stringType
        ) || isSyntheticStringLikeType(
            sema.types.makeNonNullable(receiverType),
            sema: sema
        )
        // Concrete collection receivers retain their existing owner-specific paths.
        let isIterableIndexReceiver = !isSequenceReceiver
            && !receiverClassifier.isCollectionLikeType(receiverType)
            && receiverClassifier.isNominalIterableType(receiverType)
        // Range/Progression aggregates have an independent runtime dispatch
        // family. Keep that ownership out of the Iterable source migration.
        let isRangeReceiver = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: receiverID,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ) != nil
        let isULongProgressionFirstLastCall = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: receiverID,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ) == .ulongProgression
            && args.isEmpty
            && knownNames.progressionFirstLastMemberNames.contains(calleeName)
        let isActiveCollectionHOFName: Bool = {
            // zip is source-backed. Regular overload resolution must validate the
            // other collection/Sequence argument and respect user extensions.
            guard knownNames.collectionHOFNames.contains(calleeName),
                  calleeName != knownNames.zip
            else { return false }
            if !isMutableListReceiver, knownNames.mutableListOnlyCollectionHOFNames.contains(calleeName) {
                return false
            }
            if !isSequenceReceiver {
                if calleeName == knownNames.flatMapIndexed,
                   (!isIterableReceiver
                       || receiverClassification.isListReceiver
                       || receiverClassification.isSetReceiver
                       || receiverClassification.isMapReceiver)
                {
                    return false
                }
            } else if knownNames.sequenceExcludedCollectionHOFNames.contains(calleeName) {
                return false
            }
            if isMapReceiver, !knownNames.mapCollectionHOFNames.contains(calleeName) {
                return false
            }
            return true
        }()
        let calleeStr = interner.resolve(calleeName)
        if calleeStr == "flatten", !isSequenceReceiver {
            // Let overload resolution choose between List<List<T>> and
            // Iterable<Iterable<T>> using the nested receiver's variance.
            return nil
        }
        let isPrimitiveOperatorReducerReference: Bool = {
            guard calleeStr == "reduce",
                  explicitTypeArgs.isEmpty,
                  args.count == 1,
                  let argument = args.first,
                  !argument.isSpread,
                  argument.label == nil || argument.label == interner.intern("operation"),
                  case let .callableRef(receiver?, member, _) = ast.arena.expr(argument.expr),
                  ast.arena.callableRefReceiverTypeRef(for: argument.expr) == nil,
                  case let .nameRef(receiverName, _) = ast.arena.expr(receiver),
                  locals[receiverName] == nil,
                  let primitive = driver.builtinTypeNamesCache.primitiveType(for: receiverName),
                  ["plus", "times"].contains(interner.resolve(member))
            else {
                return false
            }
            switch primitive {
            case .int, .long, .uint, .ulong, .float, .double:
                return true
            case .boolean, .char, .ubyte, .ushort, .byte, .short:
                return false
            }
        }()
        // Explicit or annotated List.reduce calls need ordinary applicability
        // and distinct S/T types. Unannotated binary lambdas and primitive
        // operator references without type arguments use the receiver element
        // context (S = T).
        if calleeStr == "reduce",
           let listOwner = sema.symbols.lookupNominal(fqName: knownNames.kotlinCollectionsListFQName),
           driver.helpers.allNominalSymbols(of: receiverType, types: sema.types, symbols: sema.symbols).contains(where: {
               sema.types.isNominalSubtypeSymbol($0, of: listOwner)
           })
        {
            guard explicitTypeArgs.isEmpty,
                  args.count == 1,
                  let argument = args.first,
                  !argument.isSpread,
                  argument.label == nil || argument.label == interner.intern("operation")
            else {
                return nil
            }
            let isUnannotatedBinaryLambda: Bool
            if case let .lambdaLiteral(parameters, _, _, _) = ast.arena.expr(argument.expr) {
                isUnannotatedBinaryLambda = parameters.count == 2
                    && ast.arena.lambdaParamTypeRefs(for: argument.expr)?.contains(where: { $0 != nil }) != true
            } else {
                isUnannotatedBinaryLambda = false
            }
            guard isUnannotatedBinaryLambda || isPrimitiveOperatorReducerReference else {
                return nil
            }
            var scopedCandidates = ctx.scope.lookupMergingChain(calleeName)
            if let local = locals[calleeName] {
                scopedCandidates.append(local.symbol)
            }
            let hasUserExtension = ctx.filterByVisibility(scopedCandidates).visible.contains { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      let site = symbol.declSite,
                      driver.sourceManager?.origin(of: site.start.file) == .user,
                      !isHiddenByDeprecationOrVersionAnnotation(candidate, symbols: sema.symbols),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      parameterMappingForCallArguments(args, in: signature, callRange: range, ctx: ctx) != nil
                else {
                    return false
                }
                return extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: sema.types.makeNonNullable(receiverType),
                    declaredReceiver: receiver,
                    sema: sema
                )
            }
            if hasUserExtension {
                return nil
            }
        }
        // KUU-4476: the fast path below only models the bundled
        // `partition(predicate)` shape — `case "partition"` binds anyType for
        // any other arity. A user-declared `partition` extension (e.g.
        // kotlin-result's zero-argument `Iterable<Result<V, E>>.partition()`)
        // must reach regular overload resolution instead.
        if calleeStr == "partition",
           hasUserDefinedCollectionExtensionCandidate(
               named: calleeName,
               receiverType: receiverType,
               args: args,
               range: range,
               ctx: ctx,
               locals: locals
           )
        {
            return nil
        }
        // KUU-1926: the collection HOF fast path only infers count's result
        // type for Collection/Iterable receivers, leaving the callee unbound.
        // Use regular overload resolution for the bundled Iterable declarations
        // so predicate checking and inline non-local returns retain their contract.
        if calleeStr == "count",
           (isCollectionReceiver || isIterableReceiver),
           !isSequenceReceiver,
           !isSetReceiver,
           !isMapReceiver,
           !isArrayReceiver,
           !receiverClassifier.isConcreteListLikeType(receiverType)
        {
            return nil
        }
        if ["indexOf", "lastIndexOf", "subList"].contains(calleeStr),
           let listOwner = sema.symbols.lookupNominal(fqName: knownNames.kotlinCollectionsListFQName),
           driver.helpers.allNominalSymbols(of: receiverType, types: sema.types, symbols: sema.symbols).contains(where: {
               sema.types.isNominalSubtypeSymbol($0, of: listOwner)
           })
        {
            return nil
        }
        let isIterableIndexFamilyHOF = ["indexOf", "indexOfFirst", "indexOfLast"].contains(calleeStr)
        // KSP-983: a nominal Iterable receiver must use the exact bundled
        // Iterable max-family declarations. Let regular overload resolution
        // select the Comparable/Float/Double and lambda-return overloads;
        // concrete List/Set/Map/Sequence paths remain under their own owners.
        if knownNames.iterableMaxFamilyNames.contains(calleeName),
           (isCollectionReceiver || isIterableReceiver),
           !isSequenceReceiver,
           !isSetReceiver,
           !isMapReceiver,
           !isArrayReceiver,
           !receiverClassifier.isConcreteListLikeType(receiverType)
        {
            return nil
        }
        let isIterableFilterFamilyHOF = [
            "filter", "filterIndexed", "filterIndexedTo", "filterIsInstance", "filterIsInstanceTo",
            "filterNot", "filterNotNull", "filterNotNullTo", "filterNotTo", "filterTo",
        ].contains(calleeStr)
            && (!isMapReceiver || knownNames.mapFilterFamilyHOFNames.contains(calleeName))
        let isCollectionHOF = (isActiveCollectionHOFName || isIterableFilterFamilyHOF)
            && (isCollectionReceiver
                || isSequenceReceiver
                || (isIterableIndexFamilyHOF && isIterableIndexReceiver)
                || (isIterableFilterFamilyHOF && isIterableReceiver)
                || (calleeStr == "reduce" && isIterableReceiver && isPrimitiveOperatorReducerReference)
                || (calleeStr == "none" && isIterableReceiver)
                || (calleeStr == "asSequence" && isIterableReceiver)
                || ((calleeStr == "runningReduce" || calleeStr == "runningReduceIndexed") && isIterableReceiver))
            // Array.map has a dedicated bundled Array extension. Keep vararg
            // Array receivers on regular overload resolution so the source
            // function supplies the lambda's return-type constraints.
            && !(isArrayReceiver && calleeStr == "map")
            && !isULongProgressionFirstLastCall
            && !(calleeStr == "binarySearch"
                && isArrayReceiver)
            // KUU-1432: every destination HOF takes exactly two arguments
            // (destination + lambda). The destination arm below only handles
            // the arity-2 shape, so a call at any other arity fell through to
            // `default:` with a result type but no callee and lowered to a
            // phantom `_filterTo`-style symbol (LINK-0001). Skip the fast path
            // so regular overload resolution reports the missing argument
            // (SEMA-0002/SEMA-0024), matching kotlinc's "no value passed for
            // parameter" rejection.
            && !(knownNames.destinationCollectionHOFs.contains(calleeName) && args.count != 2)

        // KSP-957: the generic Iterable/Map on-family declarations are real
        // source-backed overloads. Let regular overload resolution select
        // them; the collection fast path only knows the legacy List/Sequence
        // shapes and would otherwise erase the receiver-preserving return type.
        let isSourceBackedGenericOnEach = !isSequenceReceiver
            && !isArrayReceiver
            && !isListReceiver
            && !isStringReceiver
            && (isCollectionReceiver || isIterableReceiver || isMapReceiver)
            && (calleeStr == "onEach" || calleeStr == "onEachIndexed")
        // KSP-969: bind the generic Iterable drop family for a statically
        // Iterable receiver as well as concrete collection receivers. List
        // overloads are attempted first so the more specific source-backed
        // declaration keeps winning for List values.
        let isIterableDropFamily = !isSequenceReceiver
            && (calleeStr == "drop" || calleeStr == "dropWhile")
            && (isCollectionReceiver || isIterableReceiver)
        let flow = MemberCallCollectionFlowContext(
            checker: self,
            driver: driver,
            id: id,
            receiverID: receiverID,
            calleeName: calleeName,
            args: args,
            range: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            safeCall: safeCall,
            ast: ast,
            sema: sema,
            interner: interner,
            knownNames: knownNames,
            receiverType: receiverType,
            receiverClassifier: receiverClassifier,
            receiverClassification: receiverClassification,
            isCollectionReceiver: isCollectionReceiver,
            isIterableReceiver: isIterableReceiver,
            isArrayReceiver: isArrayReceiver,
            isMapReceiver: isMapReceiver,
            isMutableListReceiver: isMutableListReceiver,
            isListReceiver: isListReceiver,
            isListFactoryReceiver: isListFactoryReceiver,
            isSyntheticSequenceReceiver: isSyntheticSequenceReceiver,
            isSequenceReceiver: isSequenceReceiver,
            isSetReceiver: isSetReceiver,
            isEnumEntriesReceiver: isEnumEntriesReceiver,
            isIterableIndexReceiver: isIterableIndexReceiver,
            isRangeReceiver: isRangeReceiver,
            calleeStr: calleeStr,
            isIterableIndexFamilyHOF: isIterableIndexFamilyHOF,
            isIterableFilterFamilyHOF: isIterableFilterFamilyHOF,
            isCollectionHOF: isCollectionHOF,
            isSourceBackedGenericOnEach: isSourceBackedGenericOnEach,
            isIterableDropFamily: isIterableDropFamily
        )

        if let inferredType = flow.inferIterableDropFamilySpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferIterableElementFamilySpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }

        if let mapIteratorType = flow.bindBundledMapIteratorSourceFunction() {
            sema.bindings.bindExprType(id, type: mapIteratorType)
            return mapIteratorType
        }

        if let inferredType = flow.inferMutableListMemberSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferAsFlowMemberSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferZipMemberSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferFilterIsInstanceSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferToCollectionSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferFilterIsInstanceToSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferFilterNotNullSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferFilterNotNullToSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferBinarySearchLambdaSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferGenericOnEachSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferCollectionHOFSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }

        if flow.didReturnNil { return nil }

        if isFlowHOF,
           let lambdaArg = args.first?.expr,
           let lambdaExpr = ast.arena.expr(lambdaArg),
           lambdaExpr.isLambdaOrCallableRef
        {
            sema.bindings.markCollectionHOFLambdaExpr(lambdaArg)
        }

        // KSP-499 Stage 3: a real bundled/user Kotlin declaration for this
        // exact (Flow owner, member name, arity) takes priority over the
        // hard-coded Flow intrinsic dispatch below — mirrors the declaration
        // priority rule already established for synthetic stub registration
        // (BundledDeclarationIndex / KSP-001-003). Without this, migrating a
        // Flow operator to real Kotlin source would compile but never run:
        // this special-case would keep intercepting the call by name.
        let flowOwnerFQNameForPriorityCheck: [InternedString]? = {
            guard case let .classType(classType) = sema.types.kind(of: receiverType),
                  let ownerSymbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return nil
            }
            return ownerSymbol.fqName
        }()
        let hasBundledFlowDeclaration = flowOwnerFQNameForPriorityCheck.map {
            sema.bundledIndex.contains(
                ownerFQName: $0,
                name: calleeName
            )
        } ?? false
        // Buffer has defaulted and named parameters, so normal overload
        // resolution must select the declaration and map its arguments.
        if isFlowReceiver,
           hasBundledFlowDeclaration,
           !["buffer", "transform", "takeWhile", "dropWhile", "catch", "retry", "retryWhen"].contains(interner.resolve(calleeName)),
           let bundledFlowType = tryBuiltinFlowMemberCall(
               id,
               calleeName: calleeName,
               receiverElementType: flowElementType,
               args: args,
               safeCall: safeCall,
               ast: ast,
               sema: sema,
               ctx: ctx,
               locals: &locals
           )
        {
            // The builtin path above supplies the contextual lambda types and
            // Flow element-type tracking. Once a Flow operator has a bundled
            // Kotlin declaration, retain that source-backed symbol as the
            // call target so lowering cannot fall back to a name-only bridge.
            let flowPackageFQName = [
                interner.intern("kotlinx"),
                interner.intern("coroutines"),
                interner.intern("flow"),
                calleeName,
            ]
            if let bundledCallee = sema.symbols.lookupAll(fqName: flowPackageFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let declaredReceiver = signature.receiverType,
                      let declaredReceiverOwner = driver.helpers.nominalSymbol(
                          of: declaredReceiver,
                          types: sema.types
                      ),
                      let declaredReceiverFQName = sema.symbols.symbol(declaredReceiverOwner)?.fqName
                else {
                    return false
                }
                // SharedFlow declares pass-through overloads with the same
                // name and arity. The Flow intrinsic path must bind the
                // source declaration for this receiver, rather than whichever
                // same-named overload happens to be first in the symbol table.
                return signature.parameterTypes.count == args.count
                    && declaredReceiverFQName == flowOwnerFQNameForPriorityCheck
            }),
               let signature = sema.symbols.functionSignature(for: bundledCallee)
            {
                func typeID(from argument: TypeArg) -> TypeID {
                    switch argument {
                    case let .invariant(type), let .out(type), let .in(type):
                        type
                    case .star:
                        sema.types.anyType
                    }
                }

                func inferTypeParameters(
                    declared: TypeID,
                    actual: TypeID,
                    substitutions: inout [SymbolID: TypeID]
                ) {
                    switch sema.types.kind(of: declared) {
                    case let .typeParam(typeParameter):
                        substitutions[typeParameter.symbol] = actual
                    case let .classType(declaredClass):
                        guard case let .classType(actualClass) = sema.types.kind(of: sema.types.makeNonNullable(actual)),
                              declaredClass.classSymbol == actualClass.classSymbol
                        else {
                            return
                        }
                        for (declaredArgument, actualArgument) in zip(declaredClass.args, actualClass.args) {
                            inferTypeParameters(
                                declared: typeID(from: declaredArgument),
                                actual: typeID(from: actualArgument),
                                substitutions: &substitutions
                            )
                        }
                    case let .functionType(declaredFunction):
                        guard case let .functionType(actualFunction) = sema.types.kind(of: actual) else {
                            return
                        }
                        if let declaredReceiver = declaredFunction.receiver,
                           let actualReceiver = actualFunction.receiver
                        {
                            inferTypeParameters(
                                declared: declaredReceiver,
                                actual: actualReceiver,
                                substitutions: &substitutions
                            )
                        }
                        for (declaredParameter, actualParameter) in zip(declaredFunction.params, actualFunction.params) {
                            inferTypeParameters(
                                declared: declaredParameter,
                                actual: actualParameter,
                                substitutions: &substitutions
                            )
                        }
                        inferTypeParameters(
                            declared: declaredFunction.returnType,
                            actual: actualFunction.returnType,
                            substitutions: &substitutions
                        )
                    default:
                        return
                    }
                }

                var substitutions: [SymbolID: TypeID] = [:]
                if let declaredReceiver = signature.receiverType {
                    inferTypeParameters(
                        declared: declaredReceiver,
                        actual: receiverType,
                        substitutions: &substitutions
                    )
                }
                for (index, parameterType) in signature.parameterTypes.enumerated()
                where index < args.count {
                    let actualType = sema.bindings.exprType(for: args[index].expr)
                        ?? driver.inferExpr(args[index].expr, ctx: ctx, locals: &locals)
                    inferTypeParameters(
                        declared: parameterType,
                        actual: actualType,
                        substitutions: &substitutions
                    )
                }
                let typeArguments = signature.typeParameterSymbols.map { substitutions[$0] ?? sema.types.anyType }
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: bundledCallee,
                    substitutedTypeArguments: typeArguments,
                    parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                ))
                sema.bindings.bindCallableTarget(id, target: .symbol(bundledCallee))
                driver.helpers.checkOptIn(
                    for: bundledCallee,
                    ctx: ctx,
                    range: range,
                    diagnostics: ctx.sema.diagnostics
                )
            }
            return bundledFlowType
        }
        if isFlowReceiver,
           !hasBundledFlowDeclaration,
           let builtinFlowType = tryBuiltinFlowMemberCall(
               id,
               calleeName: calleeName,
               receiverElementType: flowElementType,
               args: args,
               safeCall: safeCall,
               ast: ast,
               sema: sema,
               ctx: ctx,
               locals: &locals
           )
        {
            return builtinFlowType
        }
        return nil
    }

    /// True when a user-source extension (or local function) named `calleeName`
    /// is visible, receiver-compatible, and arity-compatible with `args`.
    /// The collection HOF fast path only models bundled stdlib shapes, so
    /// such a candidate must defer the call to regular overload resolution
    /// (same gate the `reduce` fast path applies inline, KUU-1926/KUU-4476).
    private func hasUserDefinedCollectionExtensionCandidate(
        named calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> Bool {
        let sema = ctx.sema
        var scopedCandidates = ctx.scope.lookupMergingChain(calleeName)
        if let local = locals[calleeName] {
            scopedCandidates.append(local.symbol)
        }
        return ctx.filterByVisibility(scopedCandidates).visible.contains { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  let site = symbol.declSite,
                  driver.sourceManager?.origin(of: site.start.file) == .user,
                  !isHiddenByDeprecationOrVersionAnnotation(candidate, symbols: sema.symbols),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let receiver = signature.receiverType,
                  parameterMappingForCallArguments(args, in: signature, callRange: range, ctx: ctx) != nil
            else {
                return false
            }
            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: sema.types.makeNonNullable(receiverType),
                declaredReceiver: receiver,
                sema: sema
            )
        }
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
