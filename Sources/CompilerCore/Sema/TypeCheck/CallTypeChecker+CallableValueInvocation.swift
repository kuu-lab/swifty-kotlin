
extension CallTypeChecker {
    func markRangeCallBindings(
        _ id: ExprID,
        chosen: SymbolID,
        returnType: TypeID,
        sema: SemaModule
    ) {
        let interner = driver.interner
        let isRangeConstructor: Bool
        let externalLinkName = sema.symbols.externalLinkName(for: chosen)
        if let externalLinkName, !CallLowerer.isSourceBackedLinkName(externalLinkName) {
            isRangeConstructor = [
                "__kk_op_rangeTo",
                "__kk_op_rangeUntil",
                "__kk_op_ulong_rangeUntil",
                "__kk_uint_rangeTo",
                "__kk_ulong_rangeTo",
                "__kk_char_rangeTo",
                "__kk_int_progression_fromClosedRange",
                "__kk_long_progression_fromClosedRange",
                "__kk_uint_progression_fromClosedRange",
                "__kk_ulong_progression_fromClosedRange",
                "__kk_char_progression_fromClosedRange",
            ].contains(externalLinkName)
        } else if let symbol = sema.symbols.symbol(chosen) {
            let name = interner.resolve(symbol.name)
            isRangeConstructor = ["rangeTo", "until", "rangeUntil", "downTo", "step", "fromClosedRange"].contains(name)
                && driver.helpers.isRangeLikeType(returnType, sema: sema, interner: interner)
        } else {
            isRangeConstructor = false
        }

        guard isRangeConstructor else { return }

        // A resolved call returning a range *interface* produces a heap
        // object — ComparableRange, an anonymous implementation, or a
        // user-defined class — never the opaque runtime range-box handle
        // these marks describe. Leave the value unmarked so `x in` dispatches
        // the object's `contains` instead of a `__kk_*_range_*` bridge that
        // would trap on a non-box handle (KUU-2941).
        if driver.helpers.isRangeInterfaceType(returnType, sema: sema, interner: interner) {
            return
        }

        sema.bindings.markRangeExpr(id)

        if let elementType = driver.helpers.rangeLikeDeclaredElementType(
            for: returnType,
            sema: sema,
            interner: interner
        ), elementType == sema.types.floatType || elementType == sema.types.doubleType {
            // Generic source-backed rangeUntil resolves through OpenEndRange<T>.
            // Preserve its concrete floating-point element type for the KIR/runtime
            // bridge, just as the legacy scalar range path does for range literals.
            sema.bindings.markFloatingPointRangeExpr(id)
            sema.bindings.bindFloatingPointRangeElementType(elementType, forExpr: id)
        }

        if let (_, symbol) = resolveClassTypeSymbol(returnType, sema: sema) {
            let className = interner.resolve(symbol.name)
            switch className {
            case "UIntRange", "UIntProgression":
                sema.bindings.markUIntRangeExpr(id)
            case "ULongRange", "ULongProgression":
                sema.bindings.markULongRangeExpr(id)
            case "CharRange", "CharProgression":
                sema.bindings.markCharRangeExpr(id)
            default:
                break
            }
        }

        // Preserve the legacy external-link-name fast paths for the residual
        // synthetic/runtime-backed operators (rangeTo, old signed rangeUntil,
        // etc.) whose return type may still be the scalar handle.
        if let externalLinkName = sema.symbols.externalLinkName(for: chosen) {
            if externalLinkName == "__kk_uint_rangeTo"
                || externalLinkName == "__kk_uint_progression_fromClosedRange"
                || (externalLinkName == "__kk_op_rangeUntil" && returnType == sema.types.uintType)
            {
                sema.bindings.markUIntRangeExpr(id)
            }
            if externalLinkName == "__kk_char_rangeTo" {
                sema.bindings.markCharRangeExpr(id)
            }
            if externalLinkName == "__kk_ulong_rangeTo"
                || externalLinkName == "__kk_ulong_progression_fromClosedRange"
                || externalLinkName == "__kk_op_ulong_rangeUntil"
                || externalLinkName == "__kk_ulong_rangeTo"
            {
                sema.bindings.markULongRangeExpr(id)
            }
        }
    }

    func bindCallAndResolveReturnType(
        _ id: ExprID,
        chosen initialCallee: SymbolID,
        resolved: ResolvedCall,
        sema: SemaModule,
        dispatchReceiverSymbol: SymbolID? = nil,
        contextParameterReceiverSymbols: [SymbolID?] = []
    ) -> TypeID {
        let chosen = nullableConsoleCallee(id, chosen: initialCallee, sema: sema)
        bindResolvedFunctionValueSamArguments(id, chosen: chosen, resolved: resolved, sema: sema)
        let resolvedDispatchReceiver = dispatchReceiverSymbol
            ?? importedObjectDispatchReceiverSymbol(for: id, callee: chosen, sema: sema)
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: resolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map(\.value),
                parameterMapping: resolved.parameterMapping,
                defaultArgumentOwner: resolved.defaultArgumentOwner,
                dispatchReceiverSymbol: resolvedDispatchReceiver,
                contextParameterReceiverSymbols: contextParameterReceiverSymbols
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        // Resolve imports, aliases, bounds and the receiver normally before
        // recording the reified argument for the native KClass fast path.
        if sema.symbols.symbol(chosen)?.fqName == ["kotlin", "reflect", "full", "findAnnotation"].map(driver.interner.intern),
           let searchType = sema.bindings.callBindings[id]?.substitutedTypeArguments.first {
            sema.bindings.bindFindAnnotationSearchType(id, type: searchType)
        }
        if sema.symbols.externalLinkName(for: chosen) == "__kk_string_split" {
            sema.bindings.markCollectionExpr(id)
        }
        let returnType: TypeID
        if let signature = sema.symbols.functionSignature(for: chosen) {
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            if let receiverType = signature.receiverType,
               case let .memberCall(receiver, _, _, _, _) = driver.ast.arena.expr(id),
               let sourceType = sema.bindings.exprType(for: receiver),
               sema.types.makeNonNullable(sourceType) == sema.types.unitType
            {
                let targetType = sema.types.substituteTypeParameters(
                    in: receiverType, substitution: resolved.substitutedTypeArguments,
                    typeVarBySymbol: typeVarBySymbol
                )
                driver.recordPlatformNullAssertion(
                    receiver, sourceType: sourceType, targetType: targetType,
                    declaredParameterType: receiverType
                )
            }
            let arguments: [CallArgument]
            switch driver.ast.arena.expr(id) {
            case let .call(_, _, args, _), let .memberCall(_, _, _, args, _),
                 let .safeMemberCall(_, _, _, args, _):
                arguments = args
            case let .binary(_, _, rhs, _):
                arguments = [CallArgument(expr: rhs)]
            default:
                arguments = []
            }
            // Unqualified extension calls need the same pin/finally lowering
            // as explicit receiver calls. Match the resolved intrinsic so user
            // functions with this name retain ordinary call semantics.
            if arguments.count == 1,
               let symbol = sema.symbols.symbol(chosen),
               symbol.flags.contains(.synthetic),
               symbol.fqName == ["kotlinx", "cinterop", "usePinned"].map(driver.interner.intern)
            {
                sema.bindings.markScopeFunctionExpr(id, kind: .scopeUsePinned)
                sema.bindings.markCollectionHOFLambdaExpr(arguments[0].expr)
            }
            for (index, argument) in arguments.enumerated() where !argument.isSpread {
                guard let parameterIndex = resolved.parameterMapping[index],
                      signature.parameterTypes.indices.contains(parameterIndex),
                      let sourceType = sema.bindings.exprType(for: argument.expr)
                else { continue }
                let targetType = sema.types.substituteTypeParameters(
                    in: signature.parameterTypes[parameterIndex],
                    substitution: resolved.substitutedTypeArguments,
                    typeVarBySymbol: typeVarBySymbol
                )
                driver.recordPlatformNullAssertion(
                    argument.expr, sourceType: sourceType, targetType: targetType,
                    declaredParameterType: signature.parameterTypes[parameterIndex]
                )
            }
            returnType = sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: resolved.substitutedTypeArguments,
                typeVarBySymbol: typeVarBySymbol
            )
        } else {
            returnType = sema.types.anyType
        }
        markRangeCallBindings(id, chosen: chosen, returnType: returnType, sema: sema)
        return returnType
    }

    func importedObjectDispatchReceiverSymbol(
        for expression: ExprID,
        callee: SymbolID,
        sema: SemaModule
    ) -> SymbolID? {
        guard let symbol = sema.symbols.symbol(callee),
              let range = driver.ast.arena.exprRange(expression),
              let file = driver.ast.file(for: range.start.file)
        else {
            return nil
        }
        let sourceName: InternedString?
        switch driver.ast.arena.expr(expression) {
        case let .call(calleeExpr, _, _, _):
            if case let .nameRef(name, _) = driver.ast.arena.expr(calleeExpr) {
                sourceName = name
            } else {
                sourceName = nil
            }
        case let .memberCall(_, name, _, _, _), let .safeMemberCall(_, name, _, _, _):
            sourceName = name
        default:
            sourceName = nil
        }
        guard let sourceName else { return nil }

        let accessorProperty = sema.symbols.accessorOwnerProperty(for: callee)
            ?? sema.symbols.parentSymbol(for: callee).flatMap { parent in
                sema.symbols.symbol(parent)?.kind == .property ? parent : nil
            }
        let importedMemberName = accessorProperty.flatMap { sema.symbols.symbol($0)?.name } ?? symbol.name
        let dispatchOwner = sema.symbols.memberExtensionOwnerSymbol(for: callee)
            ?? accessorProperty.flatMap { sema.symbols.parentSymbol(for: $0) }
            ?? sema.symbols.parentSymbol(for: callee)
        guard let dispatchOwner,
              let ownerInfo = sema.symbols.symbol(dispatchOwner),
              ownerInfo.kind == .class || ownerInfo.kind == .interface || ownerInfo.kind == .object
        else {
            return nil
        }

        for importDecl in file.imports where !importDecl.isWildcard
            && (importDecl.alias ?? importDecl.path.last) == sourceName
            && importDecl.path.last == importedMemberName
        {
            let importedObjects = sema.symbols.lookupAll(fqName: Array(importDecl.path.dropLast()))
            if let object = importedObjects.first(where: { object in
                sema.symbols.symbol(object)?.kind == .object
                    && sema.types.isNominalSubtypeSymbol(object, of: dispatchOwner)
            }) {
                return object
            }
        }
        return nil
    }

    /// Native console metadata retains a String-specialized overload. Java
    /// platform Strings must use its nullable Any? sibling so printing an empty
    /// peek does not introduce a non-null parameter assertion.
    private func nullableConsoleCallee(_ id: ExprID, chosen: SymbolID, sema: SemaModule) -> SymbolID {
        guard let symbol = sema.symbols.symbol(chosen),
              symbol.fqName.count == 3,
              Array(symbol.fqName.prefix(2)) == ["kotlin", "io"].map(driver.interner.intern),
              ["print", "println"].map(driver.interner.intern).contains(symbol.name),
              let signature = sema.symbols.functionSignature(for: chosen),
              signature.parameterTypes == [sema.types.stringType]
        else { return chosen }
        let bundled = sema.symbols.sourceFileID(for: chosen).flatMap {
            driver.sourceManager?.origin(of: $0)?.isBundledStdlib
        } == true
        guard bundled || symbol.flags.contains(.importedLibrary) || symbol.flags.contains(.synthetic)
        else { return chosen }
        let arguments: [CallArgument]
        switch driver.ast.arena.expr(id) {
        case let .call(_, _, args, _), let .memberCall(_, _, _, args, _): arguments = args
        default: return chosen
        }
        guard arguments.count == 1,
              let type = sema.bindings.exprType(for: arguments[0].expr),
              sema.types.isString(type), sema.types.nullability(of: type) == .platformType
        else { return chosen }
        guard let nullableCallee = sema.symbols.lookupAll(fqName: symbol.fqName).first(where: {
            sema.symbols.functionSignature(for: $0)?.parameterTypes == [sema.types.nullableAnyType]
        }) else { return chosen }
        // Discard a tentative String hint now that the actual parameter accepts null.
        sema.bindings.bindPlatformNullAssertion(arguments[0].expr, targetType: nil)
        return nullableCallee
    }

    /// How an extension-function-typed callee's own receiver (if any) may be
    /// supplied when the arity of `argTypes` doesn't by itself say whether
    /// argument 0 is that receiver or the first ordinary parameter.
    enum CallableValueArityPolicy {
        /// The callee type's receiver (if any) is never read from `argTypes`.
        /// The receiver, if required, comes from an implicit call context.
        case receiverNeverExplicit
        /// A bare call (`ef(...)`) accepts either the historical shape, where
        /// the receiver comes from an active implicit-receiver scope
        /// (`argTypes.count == params.count`, e.g. calling a `T.() -> Unit`
        /// value bare inside `T.run { ... }`), or the receiver supplied
        /// positionally as argument 0 (`argTypes.count == params.count + 1`,
        /// e.g. `ef(3, 4)`).
        case receiverOptionallyExplicit
        /// A member property's dispatch receiver supplies a receiver-function
        /// value's receiver when it has the required type; otherwise a
        /// receiver can be supplied as argument 0 (`holder.f(3)`).
        case receiverExplicitOrMemberDispatch(TypeID)
        /// An explicit `.invoke(...)` member call has no implicit-receiver
        /// concept: when the callee type has a receiver, it must always be
        /// supplied positionally as argument 0 (`ef.invoke(3, 4)`); there is
        /// no arity at which it may be omitted (`ef.invoke(4)` is invalid).
        case receiverRequiredExplicit
        /// `receiver.(expression)(...)` requires the callee type itself to
        /// declare an extension receiver; a plain function's first parameter
        /// cannot stand in for it.
        case receiverMustBePresent
    }

    func inferCallableValueInvocation(
        _ id: ExprID,
        calleeType: TypeID,
        callableTarget: CallableTarget?,
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        arityPolicy: CallableValueArityPolicy = .receiverNeverExplicit,
        extensionCallableExpr: ExprID? = nil
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let nonNullCalleeType = sema.types.makeNonNullable(calleeType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullCalleeType) else {
            return nil
        }
        let contextTypes = functionType.contextReceivers
        let availableContextTypes = ctx.contextReceiverTypes
            + ctx.implicitReceiverStack.map(\.type)
            + ctx.outerReceiverTypes.map(\.type)
            + (ctx.implicitReceiverType.map { [$0] } ?? [])
        func hasImplicitContextValues() -> Bool {
            contextTypes.allSatisfy { requiredType in
                if sema.types.typeContainsAnyTypeParam(requiredType) {
                    return !availableContextTypes.isEmpty
                }
                return availableContextTypes.contains { availableType in
                    sema.types.isSubtype(
                        sema.types.makeNonNullable(availableType),
                        sema.types.makeNonNullable(requiredType)
                    )
                }
            }
        }
        func receiverOffset(for argumentCount: Int) -> Int? {
            switch arityPolicy {
            case .receiverNeverExplicit:
                return 0
            case .receiverOptionallyExplicit:
                guard functionType.receiver != nil else { return 0 }
                if argumentCount == functionType.params.count + 1 { return 1 }
                if argumentCount == functionType.params.count { return 0 }
                return nil
            case let .receiverExplicitOrMemberDispatch(dispatchReceiverType):
                guard let functionReceiver = functionType.receiver else {
                    return argumentCount == functionType.params.count ? 0 : nil
                }
                if argumentCount == functionType.params.count + 1 { return 1 }
                guard argumentCount == functionType.params.count,
                      sema.types.isSubtype(
                          sema.types.makeNonNullable(dispatchReceiverType),
                          functionReceiver
                      )
                else {
                    return nil
                }
                return 0
            case .receiverRequiredExplicit:
                return functionType.receiver == nil ? 0 : 1
            case .receiverMustBePresent:
                guard functionType.receiver != nil else { return nil }
                return 1
            }
        }
        func argumentsMatch(contextArgumentCount: Int, receiverOffset: Int) -> Bool {
            guard contextArgumentCount + receiverOffset + functionType.params.count == argTypes.count else {
                return false
            }
            func contextArgumentMatches(at index: Int, expected: TypeID) -> Bool {
                let expression = args[index].expr
                let actual = argTypes[index]
                if isLambdaOrCallableRefArg(expression, ast: ast)
                    || integerLiteralFitsParameter(expression, parameterType: expected, ctx: ctx)
                    || sema.types.typeContainsAnyTypeParam(actual)
                    || sema.types.typeContainsAnyTypeParam(expected)
                {
                    return true
                }
                return sema.types.isSubtype(
                    sema.types.makeNonNullable(actual),
                    sema.types.makeNonNullable(expected)
                )
            }
            for index in 0 ..< contextArgumentCount
                where !contextArgumentMatches(at: index, expected: contextTypes[index])
            {
                return false
            }
            return true
        }
        let layout: (contextArgumentCount: Int, receiverOffset: Int)? = {
            if !contextTypes.isEmpty,
               argTypes.count >= contextTypes.count,
               let offset = receiverOffset(for: argTypes.count - contextTypes.count),
               argumentsMatch(contextArgumentCount: contextTypes.count, receiverOffset: offset)
            {
                return (contextTypes.count, offset)
            }
            guard hasImplicitContextValues(),
                  let offset = receiverOffset(for: argTypes.count),
                  argumentsMatch(contextArgumentCount: 0, receiverOffset: offset)
            else {
                return nil
            }
            return (0, offset)
        }()
        guard !args.contains(where: { $0.label != nil || $0.isSpread }),
              let layout
        else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for call.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let contextArgumentCount = layout.contextArgumentCount
        let receiverArgOffset = layout.receiverOffset
        var parameterMapping: [Int: Int] = [:]
        func contextualizedArgumentType(at index: Int, parameterType: TypeID) -> TypeID {
            guard isLambdaOrCallableRefArg(args[index].expr, ast: ast)
                || integerLiteralFitsParameter(args[index].expr, parameterType: parameterType, ctx: ctx) else {
                return argTypes[index]
            }
            return driver.inferExpr(args[index].expr, ctx: ctx, locals: &locals, expectedType: parameterType)
        }
        for contextIndex in 0 ..< contextArgumentCount {
            let argumentType = contextualizedArgumentType(at: contextIndex, parameterType: contextTypes[contextIndex])
            emitCallableValueArgumentConstraint(
                left: argumentType,
                right: contextTypes[contextIndex],
                range: ast.arena.exprRange(args[contextIndex].expr) ?? range,
                ctx: ctx
            )
        }
        if receiverArgOffset == 1, let receiverType = functionType.receiver {
            let receiverIndex = contextArgumentCount
            let argumentType = contextualizedArgumentType(at: receiverIndex, parameterType: receiverType)
            // Safe receiver invocation checks null before entering the call.
            // An assertion on the receiver expression would run before that branch.
            if case .safeMemberCall = ast.arena.expr(id) {} else {
                driver.recordPlatformNullAssertion(args[receiverIndex].expr, sourceType: argumentType, targetType: receiverType)
            }
            emitCallableValueArgumentConstraint(
                left: argumentType,
                right: receiverType,
                range: ast.arena.exprRange(args[receiverIndex].expr) ?? range,
                ctx: ctx
            )
        }
        for paramIndex in functionType.params.indices {
            let argIndex = paramIndex + receiverArgOffset + contextArgumentCount
            parameterMapping[argIndex] = paramIndex
            let argumentType = contextualizedArgumentType(at: argIndex, parameterType: functionType.params[paramIndex])
            driver.recordPlatformNullAssertion(args[argIndex].expr, sourceType: argumentType,
                                               targetType: functionType.params[paramIndex])
            emitCallableValueArgumentConstraint(
                left: argumentType,
                right: functionType.params[paramIndex],
                range: ast.arena.exprRange(args[argIndex].expr) ?? range,
                ctx: ctx
            )
        }
        if let expectedType {
            driver.emitSubtypeConstraint(
                left: functionType.returnType,
                right: expectedType,
                range: range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.sema.diagnostics
            )
        }
        // A bare receiver-function call in an escaping lambda reads an outer
        // `this` even when its body contains no ordinary member reference.
        // Record that value so capture analysis retains it and KIR supplies it.
        if receiverArgOffset == 0, let requiredReceiver = functionType.receiver,
           case .call = ast.arena.expr(id) {
            let localThis = locals[ctx.interner.intern("this")].flatMap { local in
                sema.types.isSubtype(local.type, requiredReceiver) ? local.symbol : nil
            }
            let receiverSymbol = localThis
                ?? ctx.implicitReceiverStack.reversed().first(where: {
                    sema.types.isSubtype($0.type, requiredReceiver)
                })?.symbol
                ?? ctx.outerReceiverTypes.reversed().first(where: {
                    sema.types.isSubtype($0.type, requiredReceiver)
                })?.symbol
            if let receiverSymbol {
                sema.bindings.markImplicitExtensionReceiver(id, symbol: receiverSymbol)
            }
        }
        sema.bindings.bindCallableValueCall(
            id,
            binding: CallableValueCallBinding(
                target: callableTarget,
                functionType: nonNullCalleeType,
                parameterMapping: parameterMapping,
                extensionCallableExpr: extensionCallableExpr,
                contextArgumentCount: contextArgumentCount,
                receiverArgumentOffset: receiverArgOffset
            )
        )
        if let callableTarget {
            sema.bindings.bindCallableTarget(id, target: callableTarget)
        }
        sema.bindings.bindExprType(id, type: functionType.returnType)
        return functionType.returnType
    }

    private func emitCallableValueArgumentConstraint(
        left: TypeID,
        right: TypeID,
        range: SourceRange?,
        ctx: TypeInferenceContext
    ) {
        let sema = ctx.sema
        var argumentType = left
        var parameterType = right
        if let session = ctx.builderInference, !session.isFinalized,
           session.mentionsVariable(left, types: sema.types)
               || session.mentionsVariable(right, types: sema.types)
        {
            // Function values have no candidate signature for the ordinary
            // postponed-argument collector. Preserve constraints from their
            // inputs too, including inherited contravariant nominal types.
            session.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                subtype: left, supertype: right,
                typeVarBySymbol: session.typeVarBySymbol, typeSystem: sema.types,
                blameRange: range
            ))
            let solution = ConstraintSolver().solve(
                vars: ctx.resolver.usedTypeVariables(from: session.constraints),
                constraints: session.constraints, typeSystem: sema.types
            )
            if solution.isSuccess {
                argumentType = sema.types.substituteTypeParameters(
                    in: left, substitution: solution.substitution, typeVarBySymbol: session.typeVarBySymbol
                )
                parameterType = sema.types.substituteTypeParameters(
                    in: right, substitution: solution.substitution, typeVarBySymbol: session.typeVarBySymbol
                )
            }
        }
        driver.emitSubtypeConstraint(
            left: argumentType, right: parameterType, range: range,
            solver: ConstraintSolver(), sema: sema, diagnostics: sema.diagnostics
        )
    }

    func inferFunctionTypeOrError(from type: TypeID, sema: SemaModule) -> TypeID? {
        let nonNullType = sema.types.makeNonNullable(type)
        guard case .functionType = sema.types.kind(of: nonNullType) else {
            return nil
        }
        return nonNullType
    }

    func inferLexicalExtensionCallableInvocation(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        let ctx = request.ctx
        // Function values have no infix modifier. Local infix declarations
        // resolve as function symbols through the ordinary candidate path.
        guard !ctx.ast.arena.isInfixCall(request.id) else { return nil }
        let sema = ctx.sema
        let name = request.calleeName
        let candidateType: TypeID?
        if let local = locals[name] {
            // A local `fun T.name()` is a declaration, not a function value:
            // naming it bare is rejected (KUU-3007), so leave it to the
            // ordinary candidate path that ranks it above package extensions.
            guard sema.symbols.symbol(local.symbol)?.kind != .function else { return nil }
            candidateType = local.type
        } else if let implicitReceiver = ctx.implicitReceiverType,
                  let property = driver.helpers.lookupMemberProperty(
                      named: name,
                      receiverType: sema.types.makeNonNullable(implicitReceiver),
                      sema: sema
                  ) {
            candidateType = property.type
        } else {
            candidateType = ctx.cachedScopeLookup(name).first(where: {
                sema.symbols.symbol($0)?.kind == .property
            }).flatMap { sema.symbols.propertyType(for: $0) }
        }
        guard let candidateType,
              case let .functionType(candidateFunction) = sema.types.kind(of: candidateType),
              let declaredReceiver = candidateFunction.receiver,
              sema.types.isSubtype(request.safeCall ? sema.types.makeNonNullable(receiverType) : receiverType, declaredReceiver),
              candidateFunction.params.count == request.args.count,
              !request.args.contains(where: { $0.label != nil || $0.isSpread })
        else {
            return nil
        }
        for (index, argument) in request.args.enumerated() {
            let parameter = candidateFunction.params[index]
            if case let .lambdaLiteral(parameters, _, _, _) = ctx.ast.arena.expr(argument.expr) {
                if case let .functionType(function) = sema.types.kind(of: sema.types.makeNonNullable(parameter)) {
                    if parameters.isEmpty ? function.params.count > 1 : function.params.count != parameters.count {
                        return nil
                    }
                } else if !parameters.isEmpty {
                    return nil
                }
            }
            if integerLiteralFitsParameter(argument.expr, parameterType: parameter, ctx: ctx) { continue }
            if let argumentType = sema.bindings.exprType(for: argument.expr),
               ctx.ast.arena.expr(argument.expr)?.isLambdaOrCallableRef != true,
               !sema.types.isSubtype(argumentType, parameter)
            {
                return nil
            }
        }

        let calleeExpr = ctx.ast.arena.appendExpr(.nameRef(name, request.range))
        let calleeType: TypeID
        if let local = locals[name],
           sema.symbols.symbol(local.symbol)?.kind == .function
        {
            // A local function's `locals` entry is a value binding for the
            // declared symbol, but name-ref inference rejects function
            // symbols in value position. For a local extension function,
            // re-inferring the synthesized callee also rejects its bare name
            // (KUU-3007). This is an invocation callee, not a user-written
            // function value, so bind the resolved symbol and its
            // receiver-carrying function type directly.
            sema.bindings.bindIdentifier(calleeExpr, symbol: local.symbol)
            sema.bindings.bindExprType(calleeExpr, type: local.type)
            calleeType = local.type
        } else {
            calleeType = driver.inferExpr(calleeExpr, ctx: ctx, locals: &locals)
        }
        guard case let .functionType(functionType) = sema.types.kind(of: calleeType),
              functionType.receiver != nil
        else {
            return driver.helpers.bindAndReturnErrorType(request.id, sema: sema)
        }
        guard functionType.nullability == .nonNull, request.explicitTypeArgs.isEmpty else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0024",
                "Cannot invoke nullable or type-argument-qualified function value '\(ctx.interner.resolve(name))'.",
                range: request.range
            )
            return driver.helpers.bindAndReturnErrorType(request.id, sema: sema)
        }
        let argumentTypes = request.args.enumerated().map { index, argument in
            driver.inferExpr(
                argument.expr,
                ctx: ctx,
                locals: &locals,
                expectedType: functionType.params.indices.contains(index) ? functionType.params[index] : nil
            )
        }
        let result = inferCallableValueInvocation(
            request.id,
            calleeType: calleeType,
            callableTarget: driver.helpers.callableTargetForCalleeExpr(calleeExpr, sema: sema),
            args: [CallArgument(expr: request.receiverID)] + request.args,
            argTypes: [request.safeCall ? sema.types.makeNonNullable(receiverType) : receiverType] + argumentTypes,
            range: request.range,
            ctx: ctx,
            locals: &locals,
            expectedType: request.expectedType,
            arityPolicy: .receiverRequiredExplicit,
            extensionCallableExpr: calleeExpr
        ) ?? sema.types.errorType
        // Keep the lexical reference visible to lambda/local-class capture analysis.
        if let symbol = sema.bindings.identifierSymbol(for: calleeExpr) {
            sema.bindings.bindIdentifier(request.id, symbol: symbol)
        }
        let finalType = request.safeCall ? sema.types.makeNullable(result) : result
        sema.bindings.bindExprType(request.id, type: finalType)
        return finalType
    }
}
