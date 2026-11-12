// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func tryInferMemberCallCollectionFlowSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        // `recv.name` without parentheses is property-access syntax: it can
        // only bind a property (or accessor), never one of the collection
        // functions this fast path models. A same-named extension property
        // must win over `first()`/`last()`/`count()` here, and when no
        // property applies regular resolution still binds the function so
        // enforceFunctionInvocationSyntax reports SEMA-0309 (KUU-4387).
        if request.args.isEmpty, !request.ast.arena.isExplicitCall(request.id) {
            return nil
        }
        // Primitive-array source members are bundled Kotlin extensions, not collection or
        // sequence operations. Unsigned arrays currently also classify as
        // synthetic sequences, so let exact primitive-array source lookup run
        // before the generic collection-flow fast path.
        if !collectPrimitiveArraySourceMembers(
            named: request.calleeName,
            receiverType: receiverType,
            sema: request.sema,
            interner: request.interner
        ).isEmpty {
            return nil
        }
        if !collectArraySourceBackedCandidates(
            named: request.calleeName,
            receiverType: receiverType,
            ctx: request.ctx,
            sema: request.sema,
            interner: request.interner
        ).isEmpty {
            return nil
        }
        // Fallback for receivers that were never routed through a `flow { }`/operator
        // call (e.g. a user function declared `fun f(): Flow<Int>`), so the
        // `isFlowExpr`/`isFlowSymbol` bindings were never marked. Recover the
        // same information directly from the receiver's inferred class type.
        let flowClassSymbol = request.sema.symbols.lookup(fqName: [
            request.interner.intern("kotlinx"), request.interner.intern("coroutines"),
            request.interner.intern("flow"), request.interner.intern("Flow"),
        ])
        let receiverFlowClassType: ClassType? = if let flowClassSymbol,
                                                    case let .classType(classType) = request.sema.types.kind(of: request.sema.types.makeNonNullable(receiverType)),
                                                    classType.classSymbol == flowClassSymbol
        {
            classType
        } else {
            nil
        }
        let isFlowReceiver = if request.sema.bindings.isFlowExpr(request.receiverID) {
            true
        } else if case .nameRef = request.ast.arena.expr(request.receiverID),
                  let receiverSymbol = request.sema.bindings.identifierSymbol(for: request.receiverID),
                  request.sema.bindings.isFlowSymbol(receiverSymbol)
        {
            true
        } else if receiverFlowClassType != nil {
            true
        } else {
            false
        }
        if isFlowReceiver, request.calleeName == request.interner.intern("collect") {
            let flowPackage = [request.interner.intern("kotlinx"), request.interner.intern("coroutines"), request.interner.intern("flow")]
            if request.sema.bundledIndex.contains(
                ownerFQName: flowPackage + [request.interner.intern("Flow")], name: request.calleeName, arity: request.args.count
            ) || request.sema.symbols.lookupAll(fqName: flowPackage + [request.calleeName]).contains(where: {
                request.sema.symbols.isSourceBackedSymbol($0)
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
                request.sema.types.anyType
            }
        } else if let elementType = request.sema.bindings.flowElementType(forExpr: request.receiverID) {
            elementType
        } else if case .nameRef = request.ast.arena.expr(request.receiverID),
                  let receiverSymbol = request.sema.bindings.identifierSymbol(for: request.receiverID),
                  let elementType = request.sema.bindings.flowElementType(forSymbol: receiverSymbol)
        {
            elementType
        } else {
            request.sema.types.anyType
        }
        let isFlowHOF = isFlowReceiver && request.knownNames.flowHOFNames.contains(request.calleeName)
        let receiverClassifier = ReceiverClassifier(sema: request.sema, interner: request.interner)
        let receiverClassification = receiverClassifier.classify(
            receiverID: request.receiverID,
            receiverType: receiverType,
            ast: request.ast
        )
        let isCollectionReceiver = receiverClassification.isCollectionReceiver
        let isIterableReceiver = receiverClassification.isIterableReceiver
        let isArrayReceiver = receiverClassification.isArrayReceiver
        if isArrayReceiver, request.sema.requiresResolvedLibraryCalls, request.calleeName == request.knownNames.withIndex {
            return nil
        }
        let isMapReceiver = receiverClassification.isMapReceiver
        let isMutableListReceiver = receiverClassification.isMutableListReceiver
        let isListReceiver = receiverClassification.isListReceiver
        let isListFactoryReceiver = receiverClassification.isListFactoryReceiver
        let isSyntheticSequenceReceiver = receiverClassification.isSyntheticSequenceReceiver
        let isSequenceReceiver = receiverClassification.isSequenceReceiver
        let isSetReceiver = receiverClassification.isSetReceiver
        let isEnumEntriesReceiver: Bool = {
            guard let (_, symbol) = resolveClassTypeSymbol(
                request.sema.types.makeNonNullable(receiverType),
                sema: request.sema
            ) else {
                return false
            }
            return symbol.fqName == request.knownNames.kotlinEnumsEnumEntriesFQName
        }()
        let isStringReceiver = request.sema.types.isSubtype(
            request.sema.types.makeNonNullable(receiverType),
            request.sema.types.stringType
        ) || isSyntheticStringLikeType(
            request.sema.types.makeNonNullable(receiverType),
            sema: request.sema
        )
        // Concrete collection receivers retain their existing owner-specific paths.
        let isIterableIndexReceiver = !isSequenceReceiver
            && !receiverClassifier.isCollectionLikeType(receiverType)
            && receiverClassifier.isNominalIterableType(receiverType)
        // Range/Progression aggregates have an independent runtime dispatch
        // family. Keep that ownership out of the Iterable source migration.
        let isRangeReceiver = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: request.receiverID,
            receiverType: receiverType,
            sema: request.sema,
            interner: request.interner
        ) != nil
        let isULongProgressionFirstLastCall = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: request.receiverID,
            receiverType: receiverType,
            sema: request.sema,
            interner: request.interner
        ) == .ulongProgression
            && request.args.isEmpty
            && request.knownNames.progressionFirstLastMemberNames.contains(request.calleeName)
        let isActiveCollectionHOFName: Bool = {
            // zip is source-backed. Regular overload resolution must validate the
            // other collection/Sequence argument and respect user extensions.
            guard request.knownNames.collectionHOFNames.contains(request.calleeName),
                  request.calleeName != request.knownNames.zip
            else { return false }
            if !isMutableListReceiver, request.knownNames.mutableListOnlyCollectionHOFNames.contains(request.calleeName) {
                return false
            }
            if !isSequenceReceiver {
                if request.calleeName == request.knownNames.flatMapIndexed,
                   (!isIterableReceiver
                       || receiverClassification.isListReceiver
                       || receiverClassification.isSetReceiver
                       || receiverClassification.isMapReceiver)
                {
                    return false
                }
            } else if request.knownNames.sequenceExcludedCollectionHOFNames.contains(request.calleeName) {
                return false
            }
            if isMapReceiver, !request.knownNames.mapCollectionHOFNames.contains(request.calleeName) {
                return false
            }
            return true
        }()
        let calleeStr = request.interner.resolve(request.calleeName)
        if calleeStr == "flatten", !isSequenceReceiver {
            // Let overload resolution choose between List<List<T>> and
            // Iterable<Iterable<T>> using the nested receiver's variance.
            return nil
        }
        let isPrimitiveOperatorReducerReference: Bool = {
            guard calleeStr == "reduce",
                  request.explicitTypeArgs.isEmpty,
                  request.args.count == 1,
                  let argument = request.args.first,
                  !argument.isSpread,
                  argument.label == nil || argument.label == request.interner.intern("operation"),
                  case let .callableRef(receiver?, member, _) = request.ast.arena.expr(argument.expr),
                  request.ast.arena.callableRefReceiverTypeRef(for: argument.expr) == nil,
                  case let .nameRef(receiverName, _) = request.ast.arena.expr(receiver),
                  locals[receiverName] == nil,
                  let primitive = driver.builtinTypeNamesCache.primitiveType(for: receiverName),
                  ["plus", "times"].contains(request.interner.resolve(member))
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
           let listOwner = request.sema.symbols.lookupNominal(fqName: request.knownNames.kotlinCollectionsListFQName),
           driver.helpers.allNominalSymbols(of: receiverType, types: request.sema.types, symbols: request.sema.symbols).contains(where: {
               request.sema.types.isNominalSubtypeSymbol($0, of: listOwner)
           })
        {
            guard request.explicitTypeArgs.isEmpty,
                  request.args.count == 1,
                  let argument = request.args.first,
                  !argument.isSpread,
                  argument.label == nil || argument.label == request.interner.intern("operation")
            else {
                return nil
            }
            let isUnannotatedBinaryLambda: Bool
            if case let .lambdaLiteral(parameters, _, _, _) = request.ast.arena.expr(argument.expr) {
                isUnannotatedBinaryLambda = parameters.count == 2
                    && request.ast.arena.lambdaParamTypeRefs(for: argument.expr)?.contains(where: { $0 != nil }) != true
            } else {
                isUnannotatedBinaryLambda = false
            }
            guard isUnannotatedBinaryLambda || isPrimitiveOperatorReducerReference else {
                return nil
            }
            var scopedCandidates = request.ctx.scope.lookupMergingChain(request.calleeName)
            if let local = locals[request.calleeName] {
                scopedCandidates.append(local.symbol)
            }
            let hasUserExtension = request.ctx.filterByVisibility(scopedCandidates).visible.contains { candidate in
                guard let symbol = request.sema.symbols.symbol(candidate),
                      let site = symbol.declSite,
                      driver.sourceManager?.origin(of: site.start.file) == .user,
                      !isHiddenByDeprecationOrVersionAnnotation(candidate, symbols: request.sema.symbols),
                      let signature = request.sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      parameterMappingForCallArguments(request.args, in: signature, callRange: request.range, ctx: request.ctx) != nil
                else {
                    return false
                }
                return extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: request.sema.types.makeNonNullable(receiverType),
                    declaredReceiver: receiver,
                    sema: request.sema
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
               named: request.calleeName,
               receiverType: receiverType,
               args: request.args,
               range: request.range,
               ctx: request.ctx,
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
           let listOwner = request.sema.symbols.lookupNominal(fqName: request.knownNames.kotlinCollectionsListFQName),
           driver.helpers.allNominalSymbols(of: receiverType, types: request.sema.types, symbols: request.sema.symbols).contains(where: {
               request.sema.types.isNominalSubtypeSymbol($0, of: listOwner)
           })
        {
            return nil
        }
        let isIterableIndexFamilyHOF = ["indexOf", "indexOfFirst", "indexOfLast"].contains(calleeStr)
        // KSP-983: a nominal Iterable receiver must use the exact bundled
        // Iterable max-family declarations. Let regular overload resolution
        // select the Comparable/Float/Double and lambda-return overloads;
        // concrete List/Set/Map/Sequence paths remain under their own owners.
        if request.knownNames.iterableMaxFamilyNames.contains(request.calleeName),
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
            && (!isMapReceiver || request.knownNames.mapFilterFamilyHOFNames.contains(request.calleeName))
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
            && !(request.knownNames.destinationCollectionHOFs.contains(request.calleeName) && request.args.count != 2)

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
            request: request,
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
            request.sema.bindings.bindExprType(request.id, type: mapIteratorType)
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
           let lambdaArg = request.args.first?.expr,
           let lambdaExpr = request.ast.arena.expr(lambdaArg),
           lambdaExpr.isLambdaOrCallableRef
        {
            request.sema.bindings.markCollectionHOFLambdaExpr(lambdaArg)
        }

        // KSP-499 Stage 3: a real bundled/user Kotlin declaration for this
        // exact (Flow owner, member name, arity) takes priority over the
        // hard-coded Flow intrinsic dispatch below — mirrors the declaration
        // priority rule already established for synthetic stub registration
        // (BundledDeclarationIndex / KSP-001-003). Without this, migrating a
        // Flow operator to real Kotlin source would compile but never run:
        // this special-case would keep intercepting the call by name.
        let flowOwnerFQNameForPriorityCheck: [InternedString]? = {
            guard case let .classType(classType) = request.sema.types.kind(of: receiverType),
                  let ownerSymbol = request.sema.symbols.symbol(classType.classSymbol)
            else {
                return nil
            }
            return ownerSymbol.fqName
        }()
        let hasBundledFlowDeclaration = flowOwnerFQNameForPriorityCheck.map {
            request.sema.bundledIndex.contains(
                ownerFQName: $0,
                name: request.calleeName
            )
        } ?? false
        // Buffer has defaulted and named parameters, so normal overload
        // resolution must select the declaration and map its arguments.
        if isFlowReceiver,
           hasBundledFlowDeclaration,
           !["buffer", "transform", "takeWhile", "dropWhile", "catch", "retry", "retryWhen"].contains(request.interner.resolve(request.calleeName)),
           let bundledFlowType = tryBuiltinFlowMemberCall(
               request.id,
               calleeName: request.calleeName,
               receiverElementType: flowElementType,
               args: request.args,
               safeCall: request.safeCall,
               ast: request.ast,
               sema: request.sema,
               ctx: request.ctx,
               locals: &locals
           )
        {
            // The builtin path above supplies the contextual lambda types and
            // Flow element-type tracking. Once a Flow operator has a bundled
            // Kotlin declaration, retain that source-backed symbol as the
            // call target so lowering cannot fall back to a name-only bridge.
            let flowPackageFQName = [
                request.interner.intern("kotlinx"),
                request.interner.intern("coroutines"),
                request.interner.intern("flow"),
                request.calleeName,
            ]
            if let bundledCallee = request.sema.symbols.lookupAll(fqName: flowPackageFQName).first(where: { candidate in
                guard let symbol = request.sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      request.sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = request.sema.symbols.functionSignature(for: candidate),
                      let declaredReceiver = signature.receiverType,
                      let declaredReceiverOwner = driver.helpers.nominalSymbol(
                          of: declaredReceiver,
                          types: request.sema.types
                      ),
                      let declaredReceiverFQName = request.sema.symbols.symbol(declaredReceiverOwner)?.fqName
                else {
                    return false
                }
                // SharedFlow declares pass-through overloads with the same
                // name and arity. The Flow intrinsic path must bind the
                // source declaration for this receiver, rather than whichever
                // same-named overload happens to be first in the symbol table.
                return signature.parameterTypes.count == request.args.count
                    && declaredReceiverFQName == flowOwnerFQNameForPriorityCheck
            }),
               let signature = request.sema.symbols.functionSignature(for: bundledCallee)
            {
                func typeID(from argument: TypeArg) -> TypeID {
                    switch argument {
                    case let .invariant(type), let .out(type), let .in(type):
                        type
                    case .star:
                        request.sema.types.anyType
                    }
                }

                func inferTypeParameters(
                    declared: TypeID,
                    actual: TypeID,
                    substitutions: inout [SymbolID: TypeID]
                ) {
                    switch request.sema.types.kind(of: declared) {
                    case let .typeParam(typeParameter):
                        substitutions[typeParameter.symbol] = actual
                    case let .classType(declaredClass):
                        guard case let .classType(actualClass) = request.sema.types.kind(of: request.sema.types.makeNonNullable(actual)),
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
                        guard case let .functionType(actualFunction) = request.sema.types.kind(of: actual) else {
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
                where index < request.args.count {
                    let actualType = request.sema.bindings.exprType(for: request.args[index].expr)
                        ?? driver.inferExpr(request.args[index].expr, ctx: request.ctx, locals: &locals)
                    inferTypeParameters(
                        declared: parameterType,
                        actual: actualType,
                        substitutions: &substitutions
                    )
                }
                let typeArguments = signature.typeParameterSymbols.map { substitutions[$0] ?? request.sema.types.anyType }
                request.sema.bindings.bindCall(request.id, binding: CallBinding(
                    chosenCallee: bundledCallee,
                    substitutedTypeArguments: typeArguments,
                    parameterMapping: Dictionary(uniqueKeysWithValues: request.args.indices.map { ($0, $0) })
                ))
                request.sema.bindings.bindCallableTarget(request.id, target: .symbol(bundledCallee))
                driver.helpers.checkOptIn(
                    for: bundledCallee,
                    ctx: request.ctx,
                    range: request.range,
                    diagnostics: request.ctx.sema.diagnostics
                )
            }
            return bundledFlowType
        }
        if isFlowReceiver,
           !hasBundledFlowDeclaration,
           let builtinFlowType = tryBuiltinFlowMemberCall(
               request.id,
               calleeName: request.calleeName,
               receiverElementType: flowElementType,
               args: request.args,
               safeCall: request.safeCall,
               ast: request.ast,
               sema: request.sema,
               ctx: request.ctx,
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
