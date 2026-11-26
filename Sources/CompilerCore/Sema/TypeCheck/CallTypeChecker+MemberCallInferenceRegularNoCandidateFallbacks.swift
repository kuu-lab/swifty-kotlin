// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func tryInferCallableMemberPropertyInvocation(
        _ request: MemberCallInferenceRequest,
        memberLookupType: TypeID,
        argTypes: [TypeID],
        isClassNameReceiver: Bool,
        locals: inout LocalBindings,
        maximumPropertyPriority: Int? = nil
    ) -> TypeID? {
        let invocationLocals = locals
        let isSuperReceiver = if case .superRef = request.ast.arena.expr(request.receiverID) { true } else { false }
        let memberProperty = driver.helpers.lookupMemberProperty(
            named: request.calleeName,
            receiverType: memberLookupType,
            receiverDeclaration: request.receiverDeclaration,
            sema: request.sema
        )
        if !isClassNameReceiver, !isSuperReceiver,
           !request.args.isEmpty || request.ast.arena.isExplicitCall(request.id), memberProperty == nil,
           maximumPropertyPriority.map({ $0 >= 1 }) ?? true {
            let lexicalType = locals[request.calleeName]?.type ?? request.ctx.implicitReceiverType.flatMap { receiver in
                guard let property = driver.helpers.lookupMemberProperty(named: request.calleeName, receiverType: receiver, sema: request.sema),
                      let symbol = request.sema.symbols.symbol(property.symbol),
                      request.ctx.visibilityChecker.isAccessible(symbol, fromFile: request.ctx.currentFileID, enclosingClass: request.ctx.enclosingClassSymbol)
                else { return TypeID?.none }
                return property.type
            }
            if let lexicalType,
               case let .functionType(function) = request.sema.types.kind(of: lexicalType),
               let receiver = function.receiver,
               request.sema.types.isSubtype(memberLookupType, receiver),
               maximumPropertyPriority == nil || callableValueAcceptsArgumentShape(
                   function, receiverIsExplicit: false, request: request, argTypes: argTypes, locals: invocationLocals
               ),
               let result = inferLexicalExtensionCallableInvocation(request, receiverType: memberLookupType, argumentTypes: argTypes, locals: &locals) {
                return result
            }
        }
        let callableProperty: (symbol: SymbolID, type: TypeID)? = {
            guard !isClassNameReceiver, !request.args.isEmpty || request.ast.arena.isExplicitCall(request.id) else {
                return nil
            }
            if let memberProperty {
                // After a same-named function candidate fails, only a
                // callable property may participate in the invocation
                // fallback. Check this before visibility so a private value
                // property cannot replace the function's real diagnostic.
                if maximumPropertyPriority == nil,
                   inferFunctionTypeOrError(from: memberProperty.type, sema: request.sema) == nil,
                   nominalCallablePropertyInvokeCandidates(
                       memberProperty.type,
                       request: request,
                       argTypes: argTypes,
                       locals: invocationLocals
                   ).isEmpty
                {
                    return nil
                }
                if !request.explicitTypeArgs.isEmpty,
                   inferFunctionTypeOrError(from: memberProperty.type, sema: request.sema) != nil { return nil }
                if let maximumPropertyPriority,
                   (callableInvocationScopePriority(memberProperty.symbol, named: request.calleeName, ctx: request.ctx) > maximumPropertyPriority
                       || request.sema.symbols.symbol(memberProperty.symbol).map({
                           !request.ctx.visibilityChecker.isAccessible($0, fromFile: request.ctx.currentFileID, enclosingClass: request.ctx.enclosingClassSymbol)
                       }) == true
                       || !callablePropertyAcceptsArgumentShape(
                           memberProperty.symbol, request: request, argTypes: argTypes, receiverType: memberLookupType,
                           typeOverride: memberProperty.type, locals: invocationLocals
                       )) {
                    return nil
                }
                return memberProperty
            }
            if isSuperReceiver { return nil }
            if maximumPropertyPriority == nil, request.ast.arena.isExplicitCall(request.id),
               (request.safeCall ? request.sema.types.makeNonNullable(memberLookupType) : memberLookupType) == request.sema.types.charType,
               let facade = request.sema.symbols.lookupByShortName(request.calleeName).first(where: {
                   isSyntheticCharPropertyFacadeFunction($0, ctx: request.ctx)
               }),
               let signature = request.sema.symbols.functionSignature(for: facade)
            {
                return (facade, signature.returnType)
            }
            guard let propertyType = resolveExtensionPropertyGetter(
                id: request.id, calleeName: request.calleeName, range: request.range,
                receiverType: memberLookupType, expectedType: nil, ctx: request.ctx, bindCall: false, requireInScope: true,
                invocationCandidateFilter: { property in
                        (maximumPropertyPriority.map {
                            self.callableInvocationScopePriority(property, named: request.calleeName, ctx: request.ctx) <= $0
                        } ?? true)
                            && (maximumPropertyPriority == nil || request.ctx.sema.symbols.symbol(property).map {
                                request.ctx.visibilityChecker.isAccessible($0, fromFile: request.ctx.currentFileID, enclosingClass: request.ctx.enclosingClassSymbol)
                            } == true)
                            && self.callablePropertyAcceptsArgumentShape(
                                property, request: request, argTypes: argTypes, receiverType: memberLookupType, locals: invocationLocals
                            )
                }
            ), let property = request.sema.bindings.identifierSymbol(for: request.id) else {
                return nil
            }
            return (property, propertyType)
        }()
        if let propResult = callableProperty {
            var removedArgumentDiagnostics: [(ExprID, Diagnostic)] = []
            for argument in request.args {
                guard let argumentRange = request.ast.arena.exprRange(argument.expr) else { continue }
                for removed in request.sema.diagnostics.removeErrorDiagnostics(containedIn: argumentRange) {
                    removedArgumentDiagnostics.append((argument.expr, removed))
                }
            }
            defer {
                for (argumentExpr, diagnostic) in removedArgumentDiagnostics
                where request.sema.bindings.exprType(for: argumentExpr) == request.sema.types.errorType {
                    request.sema.diagnostics.emit(diagnostic)
                }
            }
            // Kotlin requires `?.`/`!!` to call a nullable function value,
            // so a `f: ((Int) -> Int)?` property must not take this arm — a
            // null function object would reach kk_function_invoke (KUU-644).
            let isNullableFunctionValue = if case let .functionType(propFunctionType) = request.sema.types.kind(of: propResult.type) {
                propFunctionType.nullability == .nullable
            } else {
                false
            }
            let callableType = inferFunctionTypeOrError(from: propResult.type, sema: request.sema)
            let invokeName = request.interner.intern("invoke")
            let invokeCandidates: [SymbolID] = callableType == nil || isNullableFunctionValue
                ? nominalCallablePropertyInvokeCandidates(
                    propResult.type, request: request, argTypes: argTypes, locals: invocationLocals
                )
                : []
            // A property joins `receiver.name(args)` resolution only when its
            // type can actually be invoked — a function type or a type with an
            // `invoke` operator. kotlinc reports `a.f()` on a private
            // `val f: Int` as "cannot be invoked", not as a private-access
            // error, and resolves `x.next()` to a same-named member function
            // when `next` is a private non-callable property — so an
            // uninvocable member must not shadow the real member-call
            // diagnostic here (KUU-4062).
            if callableType != nil || !invokeCandidates.isEmpty,
               let propSymbol = request.sema.symbols.symbol(propResult.symbol),
               !request.ctx.visibilityChecker.isAccessible(propSymbol, fromFile: request.ctx.currentFileID, enclosingClass: request.ctx.enclosingClassSymbol)
            {
                driver.helpers.emitVisibilityError(for: propSymbol, name: request.calleeStr, range: request.range, diagnostics: request.ctx.sema.diagnostics)
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }
            if !isNullableFunctionValue,
               let callableType {
                if let callableResult = inferCallableValueInvocation(
                    request.id,
                    calleeType: callableType,
                    callableTarget: .localValue(propResult.symbol),
                    args: request.args,
                    argTypes: argTypes,
                    range: request.range,
                    ctx: request.ctx,
                    locals: &locals,
                    expectedType: request.expectedType,
                    arityPolicy: request.sema.symbols.extensionPropertyReceiverType(for: propResult.symbol) == nil
                        ? .receiverExplicitOrMemberDispatch(memberLookupType) : .receiverRequiredExplicit
                ) {
                    let finalType = request.safeCall ? request.sema.types.makeNullable(callableResult) : callableResult
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }

            if !invokeCandidates.isEmpty {
                let prepared = prepareCallArguments(
                    args: request.args, callRange: request.range, candidates: invokeCandidates,
                    contextualCallResultType: request.ctx.isCallResultDiscarded && request.ctx.isUnitCoercionContext
                        ? request.sema.types.unitType : request.expectedType,
                    explicitTypeArgs: request.explicitTypeArgs,
                    receiverType: propResult.type, ctx: request.ctx, locals: &locals
                )
                let resolved = resolveCallRespectingLambdaReturnType(
                    candidates: invokeCandidates, args: request.args, argTypes: prepared.argTypes,
                    range: request.range, calleeName: invokeName, explicitTypeArgs: request.explicitTypeArgs,
                    expectedType: request.expectedType, implicitReceiverType: propResult.type,
                    lambdaLiteralIndices: prepared.lambdaLiteralIndices,
                    inputOnlyLambdaIndices: prepared.inputOnlyLambdaIndices,
                    blockedLambdaRefinement: prepared.blockedLambdaRefinement,
                    hasUnresolvableImplicitLambdaParameter: prepared.hasUnresolvableImplicitLambdaParameter,
                    ctx: request.ctx
                )
                if let diagnostic = resolved.diagnostic {
                    request.ctx.sema.diagnostics.emit(diagnostic)
                    return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                }
                if let chosen = resolved.chosenCallee {
                    let returnType = bindCallAndResolveReturnType(request.id, chosen: chosen, resolved: resolved, sema: request.sema)
                    request.sema.bindings.markInvokeOperatorCall(request.id)
                    request.sema.bindings.bindIdentifier(request.id, symbol: propResult.symbol)
                    request.sema.bindings.bindInvokeOperatorPropertyCall(request.id, binding: InvokeOperatorPropertyBinding(
                        property: propResult.symbol, propertyType: propResult.type, resultType: returnType
                    ))
                    let finalType = request.safeCall ? request.sema.types.makeNullable(returnType) : returnType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            }
        }

        if !isClassNameReceiver, !isSuperReceiver,
           !request.args.isEmpty || request.ast.arena.isExplicitCall(request.id),
           let packageProperty = request.ctx.cachedScopeLookup(request.calleeName).first(where: {
               request.sema.symbols.symbol($0)?.kind == .property
                   && request.sema.symbols.extensionPropertyReceiverType(for: $0) == nil
           }),
           request.ctx.cachedSymbol(packageProperty).map({
               request.ctx.visibilityChecker.isAccessible($0, fromFile: request.ctx.currentFileID, enclosingClass: request.ctx.enclosingClassSymbol)
           }) == true,
           maximumPropertyPriority.map({
               callableInvocationScopePriority(packageProperty, named: request.calleeName, ctx: request.ctx) <= $0
           }) ?? true,
           callablePropertyAcceptsArgumentShape(
               packageProperty, request: request, argTypes: argTypes,
               receiverType: memberLookupType, locals: invocationLocals
           ),
           let result = inferLexicalExtensionCallableInvocation(request, receiverType: memberLookupType, argumentTypes: argTypes, locals: &locals) {
            return result
        }

        return nil
    }

    func inferEnumEntryInvokeCall(
        _ request: MemberCallInferenceRequest,
        memberLookupType: TypeID,
        classNameReceiverNominalSymbol: SymbolID?,
        locals: inout LocalBindings
    ) -> TypeID? {
        guard !request.safeCall,
              let ownerSymbol = classNameReceiverNominalSymbol,
              let owner = request.sema.symbols.symbol(ownerSymbol),
              owner.kind == .enumClass
        else {
            return nil
        }

        func canonicalSymbol(_ symbol: SymbolID) -> SymbolID {
            request.sema.symbols.actualSymbol(for: symbol) ?? symbol
        }

        guard let entrySymbol = request.sema.symbols.lookupAll(fqName: owner.fqName + [request.calleeName]).first(where: { candidate in
            guard let candidateInfo = request.sema.symbols.symbol(candidate),
                  let candidateOwner = request.sema.symbols.enumOwnerSymbol(for: candidateInfo)
            else {
                return false
            }
            return canonicalSymbol(candidateOwner) == canonicalSymbol(ownerSymbol)
        }),
        let entryInfo = request.sema.symbols.symbol(entrySymbol)
        else {
            return nil
        }

        let range = request.range
        let entryName = request.ctx.interner.resolve(request.calleeName)
        guard request.ctx.visibilityChecker.isAccessible(
            entryInfo,
            fromFile: request.ctx.currentFileID,
            enclosingClass: request.ctx.enclosingClassSymbol
        ) else {
            driver.helpers.emitVisibilityError(
                for: entryInfo,
                name: entryName,
                range: range,
                diagnostics: request.sema.diagnostics
            )
            return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
        }

        let entryType = request.sema.symbols.propertyType(for: entrySymbol)
            ?? request.sema.types.makeNonNullable(memberLookupType)
        let invokeName = request.ctx.interner.intern("invoke")
        let invokeCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: invokeName,
            receiverType: entryType,
            sema: request.sema,
            interner: request.ctx.interner
        ).filter { candidate in
            request.sema.symbols.symbol(candidate)?.flags.contains(.operatorFunction) == true
        }
        guard !invokeCandidates.isEmpty else {
            return nil
        }

        let visibleCandidates = invokeCandidates.filter { candidate in
            guard let symbol = request.sema.symbols.symbol(candidate) else { return false }
            return request.ctx.visibilityChecker.isAccessible(
                symbol,
                fromFile: request.ctx.currentFileID,
                enclosingClass: request.ctx.enclosingClassSymbol
            )
        }
        guard !visibleCandidates.isEmpty else {
            if let firstInvisible = invokeCandidates.first,
               let symbol = request.sema.symbols.symbol(firstInvisible)
            {
                driver.helpers.emitVisibilityError(
                    for: symbol,
                    name: request.ctx.interner.resolve(invokeName),
                    range: range,
                    diagnostics: request.sema.diagnostics
                )
            }
            return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
        }

        let prepared = prepareCallArguments(
            args: request.args,
            callRange: range,
            candidates: visibleCandidates,
            contextualCallResultType: request.ctx.isCallResultDiscarded && request.ctx.isUnitCoercionContext
                ? request.sema.types.unitType : request.expectedType,
            explicitTypeArgs: request.explicitTypeArgs,
            receiverType: entryType,
            ctx: request.ctx,
            locals: &locals
        )
        let resolved = resolveCallRespectingLambdaReturnType(
            candidates: visibleCandidates,
            args: request.args,
            argTypes: prepared.argTypes,
            range: range,
            calleeName: invokeName,
            explicitTypeArgs: request.explicitTypeArgs,
            expectedType: request.expectedType,
            implicitReceiverType: entryType,
            lambdaLiteralIndices: prepared.lambdaLiteralIndices,
            inputOnlyLambdaIndices: prepared.inputOnlyLambdaIndices,
            blockedLambdaRefinement: prepared.blockedLambdaRefinement,
            hasUnresolvableImplicitLambdaParameter: prepared.hasUnresolvableImplicitLambdaParameter,
            ctx: request.ctx
        )
        if let diagnostic = resolved.diagnostic {
            request.sema.diagnostics.emit(diagnostic)
            return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
        }
        guard let chosen = resolved.chosenCallee else {
            return nil
        }

        let returnType = bindCallAndResolveReturnType(
            request.id,
            chosen: chosen,
            resolved: resolved,
            sema: request.sema
        )
        applyContractEffects(
            id: request.id,
            chosen: chosen,
            args: request.args,
            ctx: request.ctx,
            locals: &locals
        )
        request.sema.bindings.markInvokeOperatorCall(request.id)
        request.sema.bindings.bindEnumEntryInvokeReceiver(request.id, symbol: entrySymbol)
        request.sema.bindings.bindExprType(request.id, type: returnType)
        return returnType
    }

    func inferRegularMemberCallWithoutCandidates(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        lookupReceiverType: TypeID,
        memberLookupType: TypeID,
        argTypes: [TypeID],
        isClassNameReceiver: Bool,
        classNameReceiverNominalSymbol: SymbolID?,
        isNullLiteralReceiver: Bool,
        isFlowReceiver: Bool,
        flowElementType: TypeID,
        hasLeadingLocaleArgument: Bool,
        invisibleCandidates: [SemanticSymbol],
        isSuperCall: Bool,
        locals: inout LocalBindings
    ) -> TypeID {
        if isClassNameReceiver,
           request.args.isEmpty,
           let classNameReceiverNominalSymbol,
           let staticMember = resolveClassNameMemberValue(
               ownerNominalSymbol: classNameReceiverNominalSymbol,
               memberName: request.calleeName,
               sema: request.sema
           ),
           !(receiverQualifierIsTypeAlias(receiverID: request.receiverID, ctx: request.ctx)
               && request.sema.symbols.symbol(staticMember.symbol)?.kind == .object),
           !(request.ast.arena.isExplicitCall(request.id)
               && request.sema.symbols.symbol(staticMember.symbol)?.kind == .object)
        {
            if let memberSymbol = request.sema.symbols.symbol(staticMember.symbol),
               !request.ctx.visibilityChecker.isAccessible(
                   memberSymbol,
                   fromFile: request.ctx.currentFileID,
                   enclosingClass: request.ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(for: memberSymbol, name: request.calleeStr, range: request.range, diagnostics: request.ctx.sema.diagnostics)
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }
            request.sema.bindings.bindIdentifier(request.id, symbol: staticMember.symbol)
            request.sema.bindings.bindExprType(request.id, type: staticMember.type)
            return staticMember.type
        }
        if request.args.isEmpty,
           !request.ast.arena.isExplicitCall(request.id),
           request.calleeStr == "length"
        {
            let receiverTypeForCheck = request.safeCall
                ? request.sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if request.sema.types.isSubtype(receiverTypeForCheck, request.sema.types.stringType) {
                let resultType = request.sema.types.intType
                let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
            if !request.safeCall,
               request.sema.types.nullability(of: lookupReceiverType) == .nullable,
               request.sema.types.isSubtype(request.sema.types.makeNonNullable(lookupReceiverType), request.sema.types.stringType)
            {
                request.ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0026",
                    "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.",
                    range: request.range
                )
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }
        }
        if request.args.isEmpty,
           !request.ast.arena.isExplicitCall(request.id),
           request.calleeStr == "code"
        {
            let receiverTypeForCheck = request.safeCall
                ? request.sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverTypeForCheck == request.sema.types.charType {
                let resultType = request.sema.types.intType
                let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }
        if request.args.isEmpty {
            let receiverTypeForCheck = request.safeCall
                ? request.sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverTypeForCheck == request.sema.types.charType {
                if let member = syntheticCharMemberSpec(named: request.calleeStr),
                   !request.ast.arena.isExplicitCall(request.id) || !["code", "category", "directionality"].contains(request.calleeStr)
                {
                    let resultType = member.returnKind.typeID(
                        in: request.sema.types,
                        symbols: request.sema.symbols,
                        interner: request.interner
                    )
                    let kotlinTextFQName = [
                        request.interner.intern("kotlin"),
                        request.interner.intern("text"),
                        request.calleeName,
                    ]
                    if let chosen = request.sema.symbols.lookupAll(fqName: kotlinTextFQName).first(where: { symbolID in
                        guard let signature = request.sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.receiverType == request.sema.types.charType
                            && signature.parameterTypes.isEmpty
                    }) {
                        _ = bindCallAndResolveReturnType(
                            request.id,
                            chosen: chosen,
                            resolved: ResolvedCall(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [:],
                                parameterMapping: [:],
                                diagnostic: nil
                            ),
                            sema: request.sema
                        )
                    }
                    let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            }
        }
        if request.args.count == 1, request.calleeStr == "digitToInt" {
            let receiverTypeForCheck = request.safeCall
                ? request.sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverTypeForCheck == request.sema.types.charType {
                _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: request.sema.types.intType)
                let intType = request.sema.types.intType
                let finalType = request.safeCall ? request.sema.types.makeNullable(intType) : intType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }
        if request.args.count == 1, request.calleeStr == "digitToIntOrNull" {
            let receiverTypeForCheck = request.safeCall
                ? request.sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverTypeForCheck == request.sema.types.charType {
                _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: request.sema.types.intType)
                let resultType = request.sema.types.makeNullable(request.sema.types.intType)
                let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }
        do {
            let receiverTypeForCheck = request.safeCall
                ? request.sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if request.sema.types.isSubtype(receiverTypeForCheck, request.sema.types.booleanType) {
                if request.calleeStr == "not", request.args.isEmpty {
                    let resultType = request.sema.types.booleanType
                    let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
                if request.calleeStr == "and" || request.calleeStr == "or" || request.calleeStr == "xor", request.args.count == 1 {
                    _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: request.sema.types.booleanType)
                    let resultType = request.sema.types.booleanType
                    let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            }
        }
        do {
            let receiverTypeForCheck = request.safeCall
                ? request.sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let isSupportedHexReceiver =
                (request.calleeStr == "toHexString" && (receiverTypeForCheck == request.sema.types.intType || receiverTypeForCheck == request.sema.types.longType))
                    || (request.calleeStr == "hexToInt" && receiverTypeForCheck == request.sema.types.stringType)
                    || (request.calleeStr == "hexToShort" && receiverTypeForCheck == request.sema.types.stringType)
                    || (request.calleeStr == "hexToUByte" && receiverTypeForCheck == request.sema.types.stringType)
                    || (request.calleeStr == "hexToUShort" && receiverTypeForCheck == request.sema.types.stringType)
                    || (request.calleeStr == "hexToUByteArray" && receiverTypeForCheck == request.sema.types.stringType)
                    || (request.calleeStr == "hexToUInt" && receiverTypeForCheck == request.sema.types.stringType)
                    || (request.calleeStr == "hexToULong" && receiverTypeForCheck == request.sema.types.stringType)
            if isSupportedHexReceiver, request.args.count <= 1 {
                let kotlinTextPkg: [InternedString] = [request.interner.intern("kotlin"), request.interner.intern("text")]
                let functionFQName = kotlinTextPkg + [request.calleeName]
                let hexFormatFQName = kotlinTextPkg + [request.interner.intern("HexFormat")]
                let hexFormatType: TypeID? = {
                    guard let hexFormatSymbol = request.sema.symbols.lookup(fqName: hexFormatFQName) else { return nil }
                    return request.sema.types.make(.classType(ClassType(classSymbol: hexFormatSymbol, args: [], nullability: .nonNull)))
                }()
                if let chosen = request.sema.symbols.lookupAll(fqName: functionFQName).first(where: { candidate in
                    guard let signature = request.sema.symbols.functionSignature(for: candidate),
                          signature.receiverType == receiverTypeForCheck,
                          request.args.count <= signature.parameterTypes.count
                    else { return false }
                    if request.args.count < signature.parameterTypes.count,
                       !signature.valueParameterHasDefaultValues.dropFirst(request.args.count).allSatisfy({ $0 }) {
                        return false
                    }
                    return request.args.isEmpty || signature.parameterTypes.first == hexFormatType
                }) {
                    if request.args.count == 1, let hexFormatType {
                        _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: hexFormatType)
                    }
                    driver.helpers.checkOptIn(for: chosen, ctx: request.ctx, range: request.range, diagnostics: request.ctx.sema.diagnostics)
                    let returnType = bindCallAndResolveReturnType(
                        request.id,
                        chosen: chosen,
                        resolved: ResolvedCall(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [:],
                            parameterMapping: request.args.count == 1 ? [0: 0] : [:],
                            diagnostic: nil
                        ),
                        sema: request.sema
                    )
                    request.sema.bindings.bindExprType(request.id, type: request.safeCall ? request.sema.types.makeNullable(returnType) : returnType)
                    return request.safeCall ? request.sema.types.makeNullable(returnType) : returnType
                }
            }
        }
        if request.args.isEmpty {
            if !isNullLiteralReceiver,
               request.calleeStr == "isNullOrEmpty",
               isNullableCollectionIsNullOrEmptyReceiver(lookupReceiverType, sema: request.sema, interner: request.interner)
            {
                let resultType = request.sema.types.booleanType
                request.sema.bindings.bindExprType(request.id, type: resultType)
                return resultType
            }
            if !isNullLiteralReceiver,
               request.calleeStr == "isNullOrEmpty" || request.calleeStr == "isNullOrBlank"
            {
                let baseType = request.sema.types.makeNonNullable(lookupReceiverType)
                if request.sema.types.isSubtype(baseType, request.sema.types.stringType) {
                    let resultType = request.sema.types.booleanType
                    request.sema.bindings.bindExprType(request.id, type: resultType)
                    return resultType
                }
            }
            if !isNullLiteralReceiver,
               request.calleeStr == "toBoolean"
            {
                let baseType = request.sema.types.makeNonNullable(lookupReceiverType)
                if request.sema.types.isSubtype(baseType, request.sema.types.stringType) {
                    let resultType = request.sema.types.booleanType
                    request.sema.bindings.bindExprType(request.id, type: resultType)
                    return resultType
                }
            }
        }
        let stringHOFReceiverType = request.safeCall
            ? request.sema.types.makeNonNullable(lookupReceiverType)
            : lookupReceiverType
        if request.sema.types.isSubtype(stringHOFReceiverType, request.sema.types.stringType),
           let boundType = tryBindSyntheticStringMemberFallback(
               request.id,
               calleeName: request.calleeName,
               receiverType: stringHOFReceiverType,
               args: request.args,
               argTypes: argTypes,
               range: request.range,
               ctx: request.ctx,
               expectedType: request.expectedType,
               explicitTypeArgs: request.explicitTypeArgs,
               safeCall: request.safeCall
           )
        {
            return boundType
        }

        let knownNames = request.knownNames
        if request.args.count == 2, request.calleeName == knownNames.replace {
            let receiverTypeForCheck = stringHOFReceiverType
            let oldType = argTypes[0]
            let newType = argTypes[1]
            // This is a compatibility fallback for older stdlib artifacts that
            // may not expose the bundled replace declarations. Keep it limited
            // to the two real overload shapes. In particular, an erroneous
            // argument type is considered a subtype of every type by the type
            // system; accepting it here can synthesize a call to the nonexistent
            // replace(Char, String) ABI instead of preserving the overload error.
            let hasSupportedArgumentShape =
                (oldType == request.sema.types.stringType && newType == request.sema.types.stringType)
                    || (oldType == request.sema.types.charType && newType == request.sema.types.charType)
            if request.sema.types.isSubtype(receiverTypeForCheck, request.sema.types.stringType),
               hasSupportedArgumentShape
            {
                let finalType = request.safeCall ? request.sema.types.makeNullable(request.sema.types.stringType) : request.sema.types.stringType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }
        if request.calleeName == knownNames.format, !hasLeadingLocaleArgument {
            let receiverTypeForCheck = request.safeCall
                ? request.sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if request.sema.types.isSubtype(receiverTypeForCheck, request.sema.types.stringType) {
                if let boundType = tryBindSyntheticStringFormatFallback(
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
            }
        }
        if let result = tryInferCallableMemberPropertyInvocation(
            request, memberLookupType: memberLookupType, argTypes: argTypes,
            isClassNameReceiver: isClassNameReceiver, locals: &locals
        ) { return result }

        if !isClassNameReceiver,
           request.calleeStr == "invoke",
           let invokeFunctionType = request.sema.types.uniqueStructuralFunctionType(for: memberLookupType)
        {
            var invokeCalleeType = memberLookupType
            if let receiver = invokeFunctionType.receiver,
               argTypes.count == invokeFunctionType.params.count + 1
            {
                // `R.() -> T`.invoke(r, args...) accepts the dispatch
                // receiver as the first regular argument — fold it into the
                // parameter list so arity checks and the runtime
                // kk_function_invoke* ABI agree on the argument order.
                invokeCalleeType = request.sema.types.make(.functionType(FunctionType(
                    contextReceivers: invokeFunctionType.contextReceivers,
                    params: [receiver] + invokeFunctionType.params,
                    returnType: invokeFunctionType.returnType,
                    isSuspend: invokeFunctionType.isSuspend,
                    nullability: invokeFunctionType.nullability,
                    throws: invokeFunctionType.`throws`
                )))
            }
            if let callableResult = inferCallableValueInvocation(
                request.id,
                calleeType: invokeCalleeType,
                callableTarget: nil,
                args: request.args,
                argTypes: argTypes,
                range: request.range,
                ctx: request.ctx,
                locals: &locals,
                expectedType: request.expectedType,
                safeCall: request.safeCall,
                calleeValueExpr: request.receiverID
            ) {
                let finalType = request.safeCall ? request.sema.types.makeNullable(callableResult) : callableResult
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }

        if lookupReceiverType == request.sema.types.errorType {
            return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
        }
        if let firstInvisible = invisibleCandidates.first {
            if let fallbackType = tryBindShadowedExtensionCallFallback(
                request,
                receiverType: receiverType,
                lookupReceiverType: lookupReceiverType,
                memberLookupType: memberLookupType,
                argTypes: argTypes,
                isClassNameReceiver: isClassNameReceiver,
                isSuperCall: isSuperCall,
                locals: &locals
            ) {
                return fallbackType
            }
            driver.helpers.emitVisibilityError(for: firstInvisible, name: request.calleeStr, range: request.range, diagnostics: request.ctx.sema.diagnostics)
            return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
        }
        if let fallbackType = tryCommonMemberCallFallbacks(
            request,
            isClassNameReceiver: isClassNameReceiver,
            collectionFallbackFirst: false,
            admitNominalIterableReceiver: true,
            locals: &locals
        ) {
            return fallbackType
        }
        if !isClassNameReceiver, isFlowReceiver {
            if request.knownNames.flowChainMemberNames.contains(request.calleeName) {
                let acceptsArity = request.calleeName == request.knownNames.single ? request.args.isEmpty : request.args.count == 1
                if request.calleeName == request.knownNames.single, acceptsArity {
                    let resultType = request.safeCall ? request.sema.types.makeNullable(flowElementType) : flowElementType
                    request.sema.bindings.bindExprType(request.id, type: resultType)
                    return resultType
                }
                if acceptsArity,
                   request.calleeName == knownNames.mapMember || request.calleeName == knownNames.filter || request.calleeName == knownNames.collect ||
                   request.calleeName == knownNames.catchName || request.calleeName == knownNames.retryWhen
                {
                    let expectsLambdaTypeConstraint = switch request.ast.arena.expr(request.args[0].expr) {
                    case .callableRef:
                        false
                    default:
                        true
                    }
                    let lambdaReturnType: TypeID = if request.calleeName == knownNames.filter || request.calleeName == knownNames.retryWhen {
                        request.sema.types.booleanType
                    } else if request.calleeName == knownNames.collect || request.calleeName == knownNames.catchName {
                        request.sema.types.unitType
                    } else {
                        request.sema.types.anyType
                    }
                    let lambdaParameterTypes: [TypeID] = if request.calleeName == knownNames.catchName {
                        [request.sema.types.anyType]
                    } else if request.calleeName == knownNames.retryWhen {
                        [request.sema.types.anyType, request.sema.types.longType]
                    } else {
                        [flowElementType]
                    }
                    let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                        params: lambdaParameterTypes,
                        returnType: lambdaReturnType,
                        isSuspend: request.calleeName == knownNames.collect,
                        nullability: .nonNull
                    )))
                    if expectsLambdaTypeConstraint {
                        _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: lambdaExpectedType)
                    } else {
                        _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals)
                    }
                }

                if acceptsArity {
                    if request.calleeName == knownNames.mapMember || request.calleeName == knownNames.filter || request.calleeName == knownNames.take ||
                        request.calleeName == knownNames.catchName || request.calleeName == knownNames.retry || request.calleeName == knownNames.retryWhen
                    {
                        request.sema.bindings.markFlowExpr(request.id)
                        let resultElementType: TypeID
                        if request.calleeName == knownNames.mapMember {
                            if case let .lambdaLiteral(_, bodyExpr, _, _) = request.ast.arena.expr(request.args[0].expr),
                               let mappedType = request.sema.bindings.exprType(for: bodyExpr)
                            {
                                resultElementType = mappedType
                            } else {
                                resultElementType = request.sema.types.anyType
                            }
                        } else {
                            resultElementType = flowElementType
                        }
                        request.sema.bindings.bindFlowElementType(resultElementType, forExpr: request.id)
                    }
                    let resultType: TypeID
                    if request.calleeName == knownNames.collect {
                        resultType = request.sema.types.unitType
                    } else {
                        let resultElement = request.sema.bindings.flowElementType(forExpr: request.id) ?? flowElementType
                        resultType = driver.helpers.makeFlowType(
                            elementType: resultElement, sema: request.sema, interner: request.interner
                        ) ?? request.sema.types.anyType
                    }
                    let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            }
        }

        let isCoroutineHandleReceiver = ReceiverClassifier(sema: request.sema, interner: request.interner)
            .isCoroutineHandleReceiverType(lookupReceiverType)
        if !isClassNameReceiver, request.args.isEmpty, isCoroutineHandleReceiver {
            if request.calleeName == knownNames.cancel || request.calleeName == knownNames.join {
                let resultType = request.sema.types.unitType
                let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
            if request.calleeName == knownNames.awaitName {
                let resultType = deferredAwaitResultType(receiverID: request.receiverID, fallback: request.sema.types.nullableAnyType, ast: request.ast, sema: request.sema)
                let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
            if knownNames.coroutineHandleBoolProperties.contains(request.calleeName) {
                let resultType = request.sema.types.booleanType
                let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }
        if request.ctx.isBuilderLambdaScope, let activeBuilderKind = request.ctx.builderKind {
            let name = request.calleeStr
            let isBuilderMember: Bool = switch activeBuilderKind {
            case .buildList, .buildSet: name == "add" && request.args.count == 1
            case .buildMap: name == "put" && request.args.count == 2
            }
            if isBuilderMember {
                _ = request.args.map { argument in
                    driver.inferExpr(argument.expr, ctx: request.ctx, locals: &locals)
                }
                request.sema.bindings.bindExprType(request.id, type: request.sema.types.unitType)
                return request.sema.types.unitType
            }
        }

        if request.calleeStr == "orEmpty", request.args.isEmpty {
            let receiverType = request.sema.bindings.exprTypes[request.receiverID] ?? request.sema.types.anyType
            let nonNullReceiverType = request.sema.types.makeNonNullable(receiverType)
            if request.sema.types.isSubtype(nonNullReceiverType, request.sema.types.stringType) {
                let resultType = request.sema.types.stringType
                request.sema.bindings.bindExprType(request.id, type: resultType)
                return resultType
            }
            if isListLikeType(nonNullReceiverType, sema: request.sema, interner: request.interner) {
                let resultType = nonNullReceiverType
                request.sema.bindings.bindExprType(request.id, type: resultType)
                return resultType
            }
            if isSequenceLikeType(nonNullReceiverType, sema: request.sema, interner: request.interner) {
                let resultType = nonNullReceiverType
                request.sema.bindings.bindExprType(request.id, type: resultType)
                return resultType
            }
            let knownNames = KnownCompilerNames(interner: request.interner)
            if let (_, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: request.sema),
               knownNames.isMapLikeSymbol(symbol)
            {
                let resultType = nonNullReceiverType
                request.sema.bindings.bindExprType(request.id, type: resultType)
                return resultType
            }
        }

        if let fallbackType = tryCollectionMemberFallback(
            request.id,
            calleeName: request.calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: request.safeCall,
            receiverID: request.receiverID,
            args: request.args,
            ctx: request.ctx,
            expectedType: request.expectedType,
            admitNominalIterableReceiver: true,
            locals: &locals
        ) {
            return fallbackType
        }

        if let fallbackType = tryBindComparatorMemberFallback(
            request.id,
            calleeName: request.calleeName,
            safeCall: request.safeCall,
            receiverType: lookupReceiverType,
            args: request.args,
            ctx: request.ctx,
            locals: &locals
        ) {
            return fallbackType
        }

        if !isClassNameReceiver,
           !request.args.isEmpty || request.ast.arena.isExplicitCall(request.id),
           let result = inferLexicalExtensionCallableInvocation(request, receiverType: receiverType, argumentTypes: argTypes, locals: &locals) {
            return result
        }

        if let local = locals[request.calleeName] {
            let localType = local.type
            // Support function values that were represented as a regular
            // function type where the first parameter is the receiver.
            // Example: `val f: StringBuilder.() -> Unit` may be encoded as
            // `(StringBuilder) -> Unit` in some contexts. A declared
            // receiver already owns that role — its `params` are all
            // ordinary value parameters, so folding `params[0]` into a
            // synthetic receiver here would accept calls missing one
            // argument (KUU-3871).
            if case let .functionType(fnType) = request.sema.types.kind(of: localType),
               fnType.receiver == nil,
               !fnType.params.isEmpty,
               request.args.count == fnType.params.count - 1,
               request.sema.types.isSubtype(
                   request.sema.types.makeNonNullable(receiverType),
                   fnType.params[0]
               )
            {
                for (index, argument) in request.args.enumerated() {
                    let expectedArgumentType = fnType.params[index + 1]
                    _ = driver.inferExpr(
                        argument.expr,
                        ctx: request.ctx,
                        locals: &locals,
                        expectedType: expectedArgumentType
                    )
                }
                let boundFunctionType = request.sema.types.make(.functionType(FunctionType(
                    receiver: fnType.params[0],
                    params: Array(fnType.params.dropFirst()),
                    returnType: fnType.returnType,
                    isSuspend: fnType.isSuspend,
                    nullability: fnType.nullability
                )))
                let resultType = fnType.returnType
                let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                request.sema.bindings.bindCallableValueCall(
                    request.id,
                    binding: CallableValueCallBinding(
                        target: .localValue(local.symbol),
                        functionType: boundFunctionType,
                        parameterMapping: [:]
                    )
                )
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }

        if request.args.isEmpty,
           let ownerSymbol = driver.helpers.nominalSymbol(
               of: request.sema.types.makeNonNullable(lookupReceiverType),
               types: request.sema.types
           ),
           let owner = request.sema.symbols.symbol(ownerSymbol),
           owner.kind == .object
        {
            let nestedOwnerFQName = owner.fqName + [request.calleeName]
            var nestedOwnerSymbols = request.sema.symbols.lookupAll(fqName: nestedOwnerFQName).filter { candidate in
                guard request.sema.symbols.parentSymbol(for: candidate) == ownerSymbol,
                      let symbol = request.sema.symbols.symbol(candidate)
                else {
                    return false
                }
                switch symbol.kind {
                case .enumClass, .object, .annotationClass:
                    return true
                default:
                    return false
                }
            }
            if nestedOwnerSymbols.isEmpty {
                let shortNameNestedOwners = request.sema.symbols.lookupByShortName(request.calleeName).filter { candidate in
                    guard request.sema.symbols.parentSymbol(for: candidate) == ownerSymbol,
                          let symbol = request.sema.symbols.symbol(candidate)
                    else {
                        return false
                    }
                    switch symbol.kind {
                    case .enumClass, .object, .annotationClass:
                        return true
                    default:
                        return false
                    }
                }
                if shortNameNestedOwners.count == 1 {
                    nestedOwnerSymbols = shortNameNestedOwners
                }
            }
            if let nestedOwner = nestedOwnerSymbols.first,
               let nestedOwnerKind = request.sema.symbols.symbol(nestedOwner)?.kind,
               nestedOwnerKind == .enumClass || nestedOwnerKind == .object
                   || (nestedOwnerKind == .annotationClass && !request.ast.arena.isExplicitCall(request.id))
            {
                let nestedType = request.sema.types.make(.classType(ClassType(
                    classSymbol: nestedOwner,
                    args: [],
                    nullability: .nonNull
                )))
                request.sema.bindings.bindIdentifier(request.id, symbol: nestedOwner)
                request.sema.bindings.bindExprType(request.id, type: nestedType)
                return nestedType
            }
        }

        if let fallbackType = tryBindShadowedExtensionCallFallback(
            request,
            receiverType: receiverType,
            lookupReceiverType: lookupReceiverType,
            memberLookupType: memberLookupType,
            argTypes: argTypes,
            isClassNameReceiver: isClassNameReceiver,
            isSuperCall: isSuperCall,
            locals: &locals
        ) {
            return fallbackType
        }

        if let invokeType = inferEnumEntryInvokeCall(
            request,
            memberLookupType: memberLookupType,
            classNameReceiverNominalSymbol: classNameReceiverNominalSymbol,
            locals: &locals
        ) {
            return invokeType
        }

        let privateMemberProbeTypes: [TypeID] = if isClassNameReceiver {
            classNameReceiverNominalSymbol.flatMap {
                driver.helpers.companionScopeType(for: $0, ctx: request.ctx)
            }.map { [$0] } ?? []
        } else {
            [memberLookupType]
        }
        let isExplicitCallShape = request.ast.arena.isExplicitCall(request.id) || !request.args.isEmpty
        if let privateMember = driver.helpers.inaccessiblePrivateQualifiedMember(
            named: request.calleeName,
            probeReceiverTypes: privateMemberProbeTypes,
            ctx: request.ctx,
            matching: { member in
                guard isExplicitCallShape,
                      member.kind == .property || member.kind == .field
                else {
                    return true
                }
                guard let ownerSymbol = request.sema.symbols.parentSymbol(for: member.id),
                      let declaredType = request.sema.symbols.propertyType(for: member.id)
                else {
                    return false
                }
                let memberType = driver.helpers.resolveMemberPropertyType(
                    declaredType,
                    receiverType: memberLookupType,
                    ownerSymbol: ownerSymbol,
                    sema: request.sema
                )
                if self.inferFunctionTypeOrError(from: memberType, sema: request.sema) != nil {
                    return true
                }
                return !self.nominalCallablePropertyInvokeCandidates(
                    memberType, request: request, argTypes: argTypes, locals: locals
                ).isEmpty
            }
        ) {
            driver.helpers.emitVisibilityError(
                for: privateMember,
                name: request.calleeStr,
                range: request.range,
                diagnostics: request.ctx.sema.diagnostics
            )
            return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
        }

        request.ctx.sema.diagnostics.error("KSWIFTK-SEMA-0024", "Unresolved member function '\(request.calleeStr)'.", range: request.range)
        return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
