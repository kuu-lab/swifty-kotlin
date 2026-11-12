// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// Bundled-stdlib extension properties, ordinary member properties and
    /// scope extension properties are all resolved before function candidate
    /// collection.
    /// Returns nil when no zero-arg property path applies.
    func tryInferRegularMemberCallPropertyAccess(
        _ request: MemberCallInferenceRequest,
        isClassNameReceiver: Bool,
        isSuperCall: Bool,
        lookupReceiverType: TypeID,
        memberLookupType: TypeID,
        callableReferenceFunctionType: TypeID?,
        locals: LocalBindings
    ) -> TypeID? {
        let extensionPropertyReceiverType = callableReferenceFunctionType ?? memberLookupType
        // Only the declaring instance can use a private backing field's narrowed type.
        let allowsBackingFieldRefinement: Bool = {
            guard let enclosingClass = request.ctx.enclosingClassSymbol,
                  case .thisRef = request.ast.arena.expr(request.receiverID),
                  case let .classType(receiverClass) = request.sema.types.kind(of: memberLookupType)
            else {
                return false
            }
            return receiverClass.classSymbol == enclosingClass
        }()
        let entryMemberProperty: (symbol: SymbolID, type: TypeID)? = {
            guard case let .thisRef(label?, _) = request.ast.arena.expr(request.receiverID),
                  let entrySymbol = request.ctx.enumEntryReceiverSymbol(forQualifiedThisLabel: label)
            else {
                return nil
            }
            return driver.helpers.lookupEnumEntryMemberProperty(
                named: request.calleeName,
                entrySymbol: entrySymbol,
                receiverType: memberLookupType,
                sema: request.sema
            )
        }()
        let memberProperty = entryMemberProperty ?? driver.helpers.lookupMemberProperty(
            named: request.calleeName,
            receiverType: memberLookupType,
            receiverDeclaration: request.receiverDeclaration,
            allowBackingFieldRefinement: allowsBackingFieldRefinement,
            sema: request.sema
        )

        if !isClassNameReceiver,
           request.args.isEmpty,
           !request.ast.arena.isExplicitCall(request.id),
           memberProperty == nil,
           let sourceFile = request.ctx.currentASTFile,
           let preferredSourcePackage = preferredBundledStdlibPackage(
               sourceFile: sourceFile,
               candidates: request.sema.symbols.lookupByShortName(request.calleeName),
               receiverType: extensionPropertyReceiverType,
               sema: request.sema
           ),
           let extensionPropertyType = resolveExtensionPropertyGetter(
               id: request.id,
               calleeName: request.calleeName,
               range: request.range,
               receiverType: extensionPropertyReceiverType,
               expectedType: request.expectedType,
               ctx: request.ctx,
               preferredSourcePackage: preferredSourcePackage
           )
        {
            let finalType = request.safeCall ? request.sema.types.makeNullable(extensionPropertyType) : extensionPropertyType
            request.sema.bindings.bindExprType(request.id, type: finalType)
            return finalType
        }
        if !isClassNameReceiver,
           request.args.isEmpty,
           !request.ast.arena.isExplicitCall(request.id),
           let boundPropResult = isSuperCall
               ? driver.helpers.lookupMemberProperty(
                   named: request.calleeName,
                   // Property reads are resolved from the receiver's static type.
                   // In particular, `super.p` must select the direct superclass
                   // declaration instead of the most-derived override.
                   receiverType: lookupReceiverType,
                   sema: request.sema
               )
               : memberProperty
        {
            // An expression-bodied function inferred ahead of source order
            // can still see a member property's header `Any?` placeholder
            // through an explicit receiver (`this.data`). Resolve it on
            // demand like the implicit-receiver path does (KUU-3944).
            var propResult = boundPropResult
            if driver.pendingPropertyTypes.contains(propResult.symbol) {
                driver.resolveInferredPropertyType(for: propResult.symbol)
                if !driver.pendingPropertyTypes.contains(propResult.symbol),
                   let refreshed = driver.helpers.lookupMemberProperty(
                       named: request.calleeName,
                       receiverType: isSuperCall ? lookupReceiverType : memberLookupType,
                       receiverDeclaration: request.receiverDeclaration,
                       allowBackingFieldRefinement: allowsBackingFieldRefinement,
                       sema: request.sema
                   )
                {
                    propResult = refreshed
                }
            }
            if let propSymbol = request.sema.symbols.symbol(propResult.symbol),
               !request.ctx.visibilityChecker.isAccessible(
                   propSymbol,
                   fromFile: request.ctx.currentFileID,
                   enclosingClass: request.ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(
                    for: propSymbol,
                    name: request.interner.resolve(request.calleeName),
                    range: request.range,
                    diagnostics: request.ctx.sema.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }
            if !request.safeCall, !isSuperCall,
               request.sema.types.nullability(of: lookupReceiverType) == .nullable
            {
                request.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0026",
                    "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.",
                    range: request.range
                )
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }
            driver.helpers.checkDeprecation(
                for: propResult.symbol,
                sema: request.sema,
                interner: request.interner,
                range: request.range,
                diagnostics: request.sema.diagnostics
            )
            driver.helpers.checkOptIn(
                for: propResult.symbol,
                ctx: request.ctx,
                range: request.range,
                diagnostics: request.sema.diagnostics
            )
            request.sema.bindings.bindIdentifier(request.id, symbol: propResult.symbol)
            request.sema.bindings.bindExprType(request.id, type: propResult.type)
            bindMemberContextPropertyGetterCall(
                request.id,
                propertySymbol: propResult.symbol,
                memberLookupType: memberLookupType,
                ctx: request.ctx
            )
            let narrowedType: TypeID? = if let reference = request.ctx.dataFlow.resolveStableReference(
                request.id, locals: locals, ast: request.ast, sema: request.sema, interner: request.interner
            ), reference.isStable {
                request.ctx.dataFlow.resolvedTypeFromFlowState(
                    request.ctx.flowState.includingMembers(from: locals), reference: reference.symbol,
                    types: request.sema.types
                )
            } else {
                nil
            }
            let propertyType = narrowedType ?? propResult.type
            let finalType = request.safeCall ? request.sema.types.makeNullable(propertyType) : propertyType
            request.sema.bindings.bindExprType(request.id, type: finalType)
            return finalType
        }
        if !isClassNameReceiver,
           request.args.isEmpty,
           !request.ast.arena.isExplicitCall(request.id),
           let extensionPropertyType = resolveExtensionPropertyGetter(
               id: request.id,
               calleeName: request.calleeName,
               range: request.range,
               receiverType: extensionPropertyReceiverType,
               expectedType: request.expectedType,
               ctx: request.ctx
           )
        {
            let finalType = request.safeCall ? request.sema.types.makeNullable(extensionPropertyType) : extensionPropertyType
            request.sema.bindings.bindExprType(request.id, type: finalType)
            return finalType
        }
        // Bundled property-style facades (the synthetic Char stubs and the
        // lastIndex/indices/javaClass/java source facades) model upstream
        // properties as zero-argument extension functions. Under property
        // syntax they occupy the property namespace, so a nearer-scope user
        // function of the same name must not shadow them (KUU-4389).
        if !isClassNameReceiver,
           !isSuperCall,
           request.args.isEmpty,
           !request.ast.arena.isExplicitCall(request.id),
           let facade = request.sema.symbols.lookupByShortName(request.calleeName).first(where: { candidate in
               guard isBundledPropertyStyleFacadeFunction(candidate, ctx: request.ctx),
                     let signature = request.sema.symbols.functionSignature(for: candidate),
                     signature.typeParameterSymbols.isEmpty,
                     let facadeReceiver = signature.receiverType,
                     extensionSyntheticFallbackReceiverMatches(
                         callSiteReceiver: extensionPropertyReceiverType,
                         declaredReceiver: facadeReceiver,
                         sema: request.sema
                     ),
                     let facadeSymbol = request.sema.symbols.symbol(candidate),
                     request.ctx.visibilityChecker.isAccessible(
                         facadeSymbol,
                         fromFile: request.ctx.currentFileID,
                         enclosingClass: request.ctx.enclosingClassSymbol
                     )
               else { return false }
               return true
           })
        {
            driver.helpers.checkDeprecation(
                for: facade,
                sema: request.sema,
                interner: request.interner,
                range: request.range,
                diagnostics: request.sema.diagnostics
            )
            driver.helpers.checkOptIn(
                for: facade,
                ctx: request.ctx,
                range: request.range,
                diagnostics: request.sema.diagnostics
            )
            let resolved = ResolvedCall(
                chosenCallee: facade,
                substitutedTypeArguments: [:],
                parameterMapping: [:],
                diagnostic: nil
            )
            let resultType = bindCallAndResolveReturnType(request.id, chosen: facade, resolved: resolved, sema: request.sema)
            let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
            request.sema.bindings.bindExprType(request.id, type: finalType)
            return finalType
        }

        return nil
    }

    /// Sits between candidate collection and overload filtering.
    /// Returns nil when no special case binds.
    func tryInferRegularMemberCallSpecialCases(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        lookupReceiverType: TypeID,
        memberLookupType: TypeID,
        argTypes: [TypeID],
        isClassNameReceiver: Bool,
        isSuperCall: Bool,
        allCandidates: inout [SymbolID],
        locals: inout LocalBindings
    ) -> TypeID? {

        let receiverClassifier = ReceiverClassifier(sema: request.sema, interner: request.interner)
        let isChannelReceiver = receiverClassifier.isChannelReceiverType(lookupReceiverType)
        if !isClassNameReceiver, isChannelReceiver {
            let memberName = request.interner.resolve(request.calleeName)
            // KSP-678: send is resolved through the bundled SendChannel member
            // so its element type, variance, and suspend contract use ordinary
            // candidate resolution. close / isClosedForReceive /
            // isClosedForSend also resolve through bundled Kotlin source;
            // only receive needs a direct result-type binding here.
            switch (memberName, request.args.count) {
            // KUU-1453: `ch.receive` without parentheses is property-access
            // syntax on a function — fall through so the invocation-syntax
            // check rejects it like any other bound function.
            case ("receive", 0) where request.ast.arena.isExplicitCall(request.id) && request.explicitTypeArgs.isEmpty:
                // This direct-call shortcut has no suspend FunctionSignature
                // binding for the post-inference context validator to inspect.
                // Only the kotlinx.coroutines Channel surface owns this rule;
                // same-named user classes continue through ordinary resolution.
                guard receiverClassifier.isKotlinxCoroutinesChannelType(lookupReceiverType) else {
                    break
                }
                driver.specialSuspendingCallNames[request.id] = memberName
                let resultType: TypeID
                if let element = resolveClassType(lookupReceiverType, sema: request.sema)?.args.first {
                    switch element {
                    case let .invariant(type), let .out(type):
                        resultType = type
                    case .in, .star:
                        // A contravariant or star projection exposes only the
                        // Channel element parameter's nullable Any upper bound.
                        resultType = request.sema.types.nullableAnyType
                    }
                } else {
                    resultType = request.sema.types.nullableAnyType
                }
                let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            default:
                break
            }
        }

        // Prefer the concrete kotlin.text String.compareTo overloads over the
        // generic Comparable<T>.compareTo member, which otherwise leaves
        // String.compareTo(String) ambiguous after both surfaces are available.
        if !isClassNameReceiver,
           request.calleeName == request.knownNames.compareTo,
           request.args.count == 1 || request.args.count == 2
        {
            let receiverTypeForCheck = request.safeCall
                ? request.sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = request.sema.types.makeNonNullable(argTypes[0])
            let stringArgMatches = request.sema.types.isSubtype(arg0Type, request.sema.types.stringType)
            let boolArgMatches = request.args.count == 1
                || request.sema.types.isSubtype(request.sema.types.makeNonNullable(argTypes[1]), request.sema.types.booleanType)
            if request.sema.types.isSubtype(receiverTypeForCheck, request.sema.types.stringType),
               stringArgMatches,
               boolArgMatches
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
                    request.id,
                    calleeName: request.calleeName,
                    receiverType: receiverTypeForCheck,
                    args: request.args,
                    argTypes: argTypes,
                    range: request.range,
                    ctx: request.ctx,
                    expectedType: request.expectedType,
                    explicitTypeArgs: request.explicitTypeArgs,
                    safeCall: request.safeCall
                ) {
                    return boundType
                }
                let finalType = request.safeCall
                    ? request.sema.types.makeNullable(request.sema.types.intType)
                    : request.sema.types.intType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }

        // KSP-1403: CharSequence.substring overloads must keep normal member
        // and user-extension precedence before the source fallback is used.
        if let boundType = tryBindSyntheticStringSubstringFallback(
            request.id,
            calleeName: request.calleeName,
            receiverType: lookupReceiverType,
            args: request.args,
            argTypes: argTypes,
            range: request.range,
            ctx: request.ctx,
            expectedType: request.expectedType,
            explicitTypeArgs: request.explicitTypeArgs,
            safeCall: request.safeCall,
            existingCandidates: allCandidates
        ) {
            return boundType
        }

        // KSP-1402: the nominal CharSequence.subSequence(Int, Int) candidate
        // shadows the source-backed IntRange extension during member lookup.
        // Resolve the range overload before the nominal candidate resolver sees
        // the scalar representation of an inline range literal.
        if let boundType = tryBindSyntheticStringRangeSubSequenceFallback(
            request.id,
            calleeName: request.calleeName,
            receiverType: lookupReceiverType,
            args: request.args,
            argTypes: argTypes,
            range: request.range,
            ctx: request.ctx,
            expectedType: request.expectedType,
            explicitTypeArgs: request.explicitTypeArgs,
            safeCall: request.safeCall,
            existingCandidates: allCandidates
        ) {
            return boundType
        }

        let stringMemberName = request.interner.resolve(request.calleeName)
        if ["minWith", "minWithOrNull"].contains(stringMemberName),
           isSyntheticStringLikeType(lookupReceiverType, sema: request.sema),
           request.args.count == 1,
           let comparatorElementType = resolvedComparatorElementType(
               of: argTypes[0],
               sema: request.sema,
               interner: request.interner
           ),
           request.sema.types.nullability(of: argTypes[0]) != .nullable,
           request.sema.types.isSubtype(request.sema.types.charType, comparatorElementType)
        {
            // The source-backed Comparator<in Char> parameter is valid for a
            // Comparator<Char> argument, but the regular resolver currently
            // rejects that variance. Bind the uniquely named CharSequence
            // declaration after the normal candidates have been considered.
            bindSyntheticStringMemberDirectlyIfAvailable(
                request.id,
                calleeName: request.calleeName,
                argumentCount: request.args.count,
                receiverType: lookupReceiverType,
                sema: request.sema,
                interner: request.interner
            )
            if request.sema.bindings.callBindings[request.id] != nil {
                let resultType = stringMemberName == "minWithOrNull"
                    ? request.sema.types.make(.primitive(.char, .nullable))
                    : request.sema.types.make(.primitive(.char, .nonNull))
                let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }

        // A lexical extension function value outranks package extensions,
        // while actual receiver members retain their usual priority.
        let hasReceiverMember = driver.helpers.collectMemberFunctionCandidates(
            named: request.calleeName, receiverType: memberLookupType, sema: request.sema, interner: request.interner
        ).contains {
            request.ctx.cachedSymbol($0)?.flags.contains(.extensionMemberAlias) != true
                && !driver.helpers.declaresExtensionReceiver($0, sema: request.sema, interner: request.interner)
        }
        let localExtensionMatchesCallShape: Bool = {
            guard let local = locals[request.calleeName],
                  request.sema.symbols.functionSignature(for: local.symbol)?.receiverType != nil
            else { return true }
            return extensionCandidateMatchesCallShape(
                local.symbol, request: request, argumentTypes: argTypes, receiverType: memberLookupType
            )
        }()
        // `a.f { }` carries a trailing lambda without `()`, so a non-empty
        // argument list counts as a call the same way `isExplicitCall` does.
        if !isSuperCall, !request.args.isEmpty || request.ast.arena.isExplicitCall(request.id),
           !hasReceiverMember,
           localExtensionMatchesCallShape,
           let result = inferLexicalExtensionCallableInvocation(request, receiverType: receiverType, argumentTypes: argTypes, locals: &locals)
        {
            return result
        }

        if !isSuperCall,
           localExtensionMatchesCallShape,
           let local = locals[request.calleeName],
           !request.ast.arena.isInfixCall(request.id) || request.sema.symbols.symbol(local.symbol)?.flags.contains(.infixFunction) == true,
           let receiver = request.sema.symbols.functionSignature(for: local.symbol)?.receiverType,
           extensionSyntheticFallbackReceiverMatches(
               callSiteReceiver: memberLookupType, declaredReceiver: receiver, sema: request.sema
           ),
           !hasReceiverMember
        {
            allCandidates = [local.symbol]
        }

        return nil
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
