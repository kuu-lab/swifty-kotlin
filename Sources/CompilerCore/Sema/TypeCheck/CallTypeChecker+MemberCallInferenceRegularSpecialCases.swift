// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// Zero-argument property access, extracted verbatim from
    /// `inferRegularMemberCall`: bundled-stdlib extension properties, ordinary
    /// member properties and scope extension properties are all resolved before
    /// function candidate collection.
    /// Returns nil when no zero-arg property path applies.
    func tryInferRegularMemberCallPropertyAccess(
        _ request: MemberCallInferenceRequest,
        isClassNameReceiver: Bool,
        isSuperCall: Bool,
        lookupReceiverType: TypeID,
        memberLookupType: TypeID,
        locals: LocalBindings
    ) -> TypeID? {
        let id = request.id
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let expectedType = request.expectedType
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        if !isClassNameReceiver,
           args.isEmpty,
           !ast.arena.isExplicitCall(id),
           driver.helpers.lookupMemberProperty(
               named: calleeName, receiverType: memberLookupType, sema: sema
           ) == nil,
           let sourceFile = ctx.currentASTFile,
           let preferredSourcePackage = preferredBundledStdlibPackage(
               sourceFile: sourceFile,
               candidates: sema.symbols.lookupByShortName(calleeName),
               receiverType: memberLookupType,
               sema: sema
           ),
           let extensionPropertyType = resolveExtensionPropertyGetter(
               id: id,
               calleeName: calleeName,
               range: range,
               receiverType: memberLookupType,
               expectedType: expectedType,
               ctx: ctx,
               preferredSourcePackage: preferredSourcePackage
           )
        {
            let finalType = safeCall ? sema.types.makeNullable(extensionPropertyType) : extensionPropertyType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        if !isClassNameReceiver,
           args.isEmpty,
           !ast.arena.isExplicitCall(id),
           let propResult = driver.helpers.lookupMemberProperty(
               named: calleeName,
               // Property reads are resolved from the receiver's static type.
               // In particular, `super.p` must select the direct superclass
               // declaration instead of the most-derived override.
               receiverType: isSuperCall ? lookupReceiverType : memberLookupType,
               sema: sema
           )
        {
            if let propSymbol = sema.symbols.symbol(propResult.symbol),
               !ctx.visibilityChecker.isAccessible(
                   propSymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(
                    for: propSymbol,
                    name: interner.resolve(calleeName),
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: propResult.symbol)
            sema.bindings.bindExprType(id, type: propResult.type)
            let narrowedType: TypeID? = if let reference = ctx.dataFlow.resolveStableReference(
                id, locals: locals, ast: ast, sema: sema, interner: interner
            ), reference.isStable {
                ctx.dataFlow.resolvedTypeFromFlowState(
                    ctx.flowState.includingMembers(from: locals), reference: reference.symbol
                )
            } else {
                nil
            }
            let propertyType = narrowedType ?? propResult.type
            let finalType = safeCall ? sema.types.makeNullable(propertyType) : propertyType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        if !isClassNameReceiver,
           args.isEmpty,
           !ast.arena.isExplicitCall(id),
           let extensionPropertyType = resolveExtensionPropertyGetter(
               id: id,
               calleeName: calleeName,
               range: range,
               receiverType: memberLookupType,
               expectedType: expectedType,
               ctx: ctx
           )
        {
            let finalType = safeCall ? sema.types.makeNullable(extensionPropertyType) : extensionPropertyType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        return nil
    }

    /// Special-cased member handling that sits between candidate collection and
    /// overload filtering, extracted verbatim from `inferRegularMemberCall`:
    /// channel send/receive, concrete String.compareTo, bundled
    /// substring/subSequence fallbacks, comparator minWith, lexical extension
    /// invocation and local extension shadowing.
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
        let id = request.id
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

        let isChannelReceiver = ReceiverClassifier(sema: sema, interner: interner)
            .isChannelReceiverType(lookupReceiverType)
        if !isClassNameReceiver, isChannelReceiver {
            let memberName = interner.resolve(calleeName)
            // KSP-678: close / isClosedForReceive / isClosedForSend are resolved
            // through bundled Kotlin source (Channels.kt) via normal candidate
            // resolution below; only the suspension core send / receive are
            // special-cased here.
            switch (memberName, args.count) {
            case ("send", 1):
                let resultType = sema.types.unitType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            // KUU-1453: `ch.receive` without parentheses is property-access
            // syntax on a function — fall through so the invocation-syntax
            // check rejects it like any other bound function.
            case ("receive", 0) where ast.arena.isExplicitCall(id):
                let resultType = sema.types.nullableAnyType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            default:
                break
            }
        }

        // Prefer the concrete kotlin.text String.compareTo overloads over the
        // generic Comparable<T>.compareTo member, which otherwise leaves
        // String.compareTo(String) ambiguous after both surfaces are available.
        if !isClassNameReceiver,
           calleeName == knownNames.compareTo,
           args.count == 1 || args.count == 2
        {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            let stringArgMatches = sema.types.isSubtype(arg0Type, sema.types.stringType)
            let boolArgMatches = args.count == 1
                || sema.types.isSubtype(sema.types.makeNonNullable(argTypes[1]), sema.types.booleanType)
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               stringArgMatches,
               boolArgMatches
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                let finalType = safeCall
                    ? sema.types.makeNullable(sema.types.intType)
                    : sema.types.intType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // KSP-1403: CharSequence.substring overloads must keep normal member
        // and user-extension precedence before the source fallback is used.
        if let boundType = tryBindSyntheticStringSubstringFallback(
            id,
            calleeName: calleeName,
            receiverType: lookupReceiverType,
            args: args,
            argTypes: argTypes,
            range: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            safeCall: safeCall,
            existingCandidates: allCandidates
        ) {
            return boundType
        }

        // KSP-1402: the nominal CharSequence.subSequence(Int, Int) candidate
        // shadows the source-backed IntRange extension during member lookup.
        // Resolve the range overload before the nominal candidate resolver sees
        // the scalar representation of an inline range literal.
        if let boundType = tryBindSyntheticStringRangeSubSequenceFallback(
            id,
            calleeName: calleeName,
            receiverType: lookupReceiverType,
            args: args,
            argTypes: argTypes,
            range: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            safeCall: safeCall,
            existingCandidates: allCandidates
        ) {
            return boundType
        }

        let stringMemberName = interner.resolve(calleeName)
        if ["minWith", "minWithOrNull"].contains(stringMemberName),
           isSyntheticStringLikeType(lookupReceiverType, sema: sema),
           args.count == 1,
           let comparatorElementType = resolvedComparatorElementType(
               of: argTypes[0],
               sema: sema,
               interner: interner
           ),
           sema.types.nullability(of: argTypes[0]) != .nullable,
           sema.types.isSubtype(sema.types.charType, comparatorElementType)
        {
            // The source-backed Comparator<in Char> parameter is valid for a
            // Comparator<Char> argument, but the regular resolver currently
            // rejects that variance. Bind the uniquely named CharSequence
            // declaration after the normal candidates have been considered.
            bindSyntheticStringMemberDirectlyIfAvailable(
                id,
                calleeName: calleeName,
                argumentCount: args.count,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
            if sema.bindings.callBindings[id] != nil {
                let resultType = stringMemberName == "minWithOrNull"
                    ? sema.types.make(.primitive(.char, .nullable))
                    : sema.types.make(.primitive(.char, .nonNull))
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // A lexical extension function value outranks package extensions,
        // while actual receiver members retain their usual priority.
        let hasReceiverMember = driver.helpers.collectMemberFunctionCandidates(
            named: calleeName, receiverType: memberLookupType, sema: sema, interner: interner
        ).contains {
            ctx.cachedSymbol($0)?.flags.contains(.extensionMemberAlias) != true
                && !driver.helpers.declaresExtensionReceiver($0, sema: sema, interner: interner)
        }
        if !isSuperCall, ast.arena.isExplicitCall(id),
           !hasReceiverMember,
           let result = inferLexicalExtensionCallableInvocation(request, receiverType: receiverType, locals: &locals)
        {
            return result
        }

        if !isSuperCall,
           let local = locals[calleeName],
           let receiver = sema.symbols.functionSignature(for: local.symbol)?.receiverType,
           extensionSyntheticFallbackReceiverMatches(
               callSiteReceiver: memberLookupType, declaredReceiver: receiver, sema: sema
           ),
           !hasReceiverMember
        {
            allCandidates = [local.symbol]
        }

        return nil
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
