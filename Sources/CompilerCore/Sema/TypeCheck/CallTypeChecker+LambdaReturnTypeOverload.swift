
extension CallTypeChecker {
    /// A qualified member import binds the named singleton, whereas lookup
    /// through a nullable implicit receiver must still check that receiver.
    /// Imported extensions keep their declared receiver even when their
    /// bundled owner is an object after header collection.
    func importedObjectDispatchReceiverCandidates(
        named name: InternedString?,
        candidates: [SymbolID],
        ctx: TypeInferenceContext
    ) -> Set<SymbolID> {
        let owners = importedObjectDispatchReceiverOwners(named: name, candidates: candidates, ctx: ctx)
        return Set(owners.keys.filter {
            ctx.sema.symbols.memberExtensionOwnerSymbol(for: $0) == nil
        })
    }

    func importedObjectDispatchReceiverOwners(
        named name: InternedString?,
        candidates: [SymbolID],
        ctx: TypeInferenceContext
    ) -> [SymbolID: SymbolID] {
        guard let name, let file = ctx.currentASTFile else { return [:] }
        let imports = file.imports.filter {
            !$0.isWildcard && ($0.alias ?? $0.path.last) == name
        }
        guard !imports.isEmpty else { return [:] }

        var result: [SymbolID: SymbolID] = [:]
        for candidate in candidates {
            guard let symbol = ctx.sema.symbols.symbol(candidate),
                  symbol.kind == .function
            else { continue }
            let accessorProperty = ctx.sema.symbols.accessorOwnerProperty(for: candidate)
                ?? ctx.sema.symbols.parentSymbol(for: candidate).flatMap { parent in
                    ctx.sema.symbols.symbol(parent)?.kind == .property ? parent : nil
                }
            let importedMemberName = accessorProperty.flatMap { ctx.sema.symbols.symbol($0)?.name }
                ?? symbol.name
            let dispatchOwner = ctx.sema.symbols.memberExtensionOwnerSymbol(for: candidate)
                ?? accessorProperty.flatMap { ctx.sema.symbols.parentSymbol(for: $0) }
                ?? ctx.sema.symbols.parentSymbol(for: candidate)
            guard let dispatchOwner,
                  let ownerSymbol = ctx.sema.symbols.symbol(dispatchOwner),
                  ownerSymbol.kind == .class || ownerSymbol.kind == .interface || ownerSymbol.kind == .object
            else { continue }

            for importDecl in imports where importDecl.path.last == importedMemberName {
                let importedObjects = ctx.sema.symbols.lookupAll(fqName: Array(importDecl.path.dropLast()))
                if let object = importedObjects.first(where: { object in
                    ctx.sema.symbols.symbol(object)?.kind == .object
                        && ctx.sema.types.isNominalSubtypeSymbol(object, of: dispatchOwner)
                }) {
                    result[candidate] = object
                    break
                }
            }
        }
        return result
    }

    /// Member extensions still need their source-level extension receiver,
    /// but an import through an object also supplies its dispatch receiver.
    func importedObjectDispatchReceiverTypes(
        named name: InternedString?,
        candidates: [SymbolID],
        ctx: TypeInferenceContext
    ) -> [TypeID] {
        let owners = Set(importedObjectDispatchReceiverOwners(named: name, candidates: candidates, ctx: ctx).values)
        return owners.sorted { $0.rawValue < $1.rawValue }.map { owner in
            ctx.sema.types.make(.classType(ClassType(
                classSymbol: owner,
                args: [],
                nullability: .nonNull
            )))
        }
    }

    struct PreparedCallArguments {
        let argTypes: [TypeID]
        let lambdaLiteralIndices: Set<Int>
        let inputOnlyLambdaIndices: Set<Int>
        let blockedLambdaRefinement: Bool
        /// True when a bare (no declared parameter list) lambda argument relies on an
        /// implicit single parameter (`it`) whose type can't be fixed before overload
        /// resolution, because the remaining candidates each expect exactly one
        /// parameter but disagree on its type (DEBT-SEMA-004). Unlike
        /// `blockedLambdaRefinement`, which only forces an ambiguity diagnostic when a
        /// candidate opts in via `@OverloadResolutionByLambdaReturnType`, this case is
        /// unresolvable regardless of that annotation: there is no locally-known type
        /// to check the lambda body against.
        let hasUnresolvableImplicitLambdaParameter: Bool
    }

    private func contextualCallableReferenceArgumentType(
        at index: Int,
        argumentLabel: InternedString?,
        args: [CallArgument],
        callRange: SourceRange,
        expectedCandidates: [SymbolID],
        callCandidates: [SymbolID],
        explicitTypeArgs: [TypeID],
        receiverType: TypeID?,
        inferredNonLambdaArgTypes: [Int: TypeID],
        callResultType: TypeID?,
        resolver: OverloadResolver?,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let expectation = callableReferenceExpectedType(
            at: index,
            argumentLabel: argumentLabel,
            args: args,
            callRange: callRange,
            candidates: expectedCandidates,
            explicitTypeArgs: explicitTypeArgs,
            receiverType: receiverType,
            inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
            resolver: resolver,
            ctx: ctx
        ) ?? lambdaLiteralExpectedType(
            at: index,
            args: args,
            callRange: callRange,
            candidates: expectedCandidates,
            explicitTypeArgs: explicitTypeArgs,
            receiverType: receiverType,
            inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
            resolver: resolver,
            sema: sema,
            ctx: ctx
        ).type
        guard let contextualType = contextualCallableArgumentType(
            expectation,
            callResultType: callResultType,
            candidates: callCandidates,
            sema: sema
        ) else {
            return nil
        }
        guard expectedCandidates.count == 1,
              let candidate = expectedCandidates.first,
              let signature = sema.symbols.functionSignature(for: candidate)
        else {
            return contextualType
        }
        return applyDispatchReceiverClassTypeArgs(
            to: contextualType,
            signature: signature,
            candidate: candidate,
            ctx: ctx
        )
    }

    func prepareCallArguments(
        args: [CallArgument],
        callRange: SourceRange,
        candidates: [SymbolID],
        preInferredNonLambdaArgTypes: [Int: TypeID] = [:],
        expectedTypeOverrides: [Int: TypeID] = [:],
        expectedTypeHintIndices: Set<Int> = [],
        contextualCallResultType: TypeID? = nil,
        explicitTypeArgs: [TypeID] = [],
        receiverType: TypeID? = nil,
        boundObjectDispatchReceiverCandidates: Set<SymbolID> = [],
        lambdaContextOverrides: [Int: TypeInferenceContext] = [:],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> PreparedCallArguments {
        let ast = ctx.ast
        let sema = ctx.sema
        var expectedTypeOverrides = expectedTypeOverrides
        if ctx.builderInference != nil,
           candidates.count == 1, let candidate = candidates.first,
           sema.symbols.symbol(candidate)?.kind != .constructor,
           let signature = sema.symbols.functionSignature(for: candidate),
           signature.classTypeParameterCount > 0,
           signature.typeParameterSymbols.count == signature.classTypeParameterCount,
           sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
           let receiver = receiverType ?? ctx.implicitReceiverType,
           let mapping = parameterMappingForCallArguments(args, in: signature, callRange: callRange, ctx: ctx)
        {
            for (argument, parameter) in mapping where expectedTypeOverrides[argument] == nil {
                guard let sourceType = contextualCallArgumentType(
                    args[argument], parameterIndex: parameter, in: signature, ctx: ctx
                ) else { continue }
                let specializedType = applyReceiverClassTypeArgs(
                    to: sourceType, signature: signature, candidate: candidate,
                    receiverType: receiver, sema: sema
                )
                guard ctx.builderInference?.mentionsVariable(specializedType, types: sema.types) != true else { continue }
                switch ast.arena.expr(args[argument].expr) {
                case .intLiteral, .uintLiteral:
                    expectedTypeOverrides[argument] = specializedType
                case let .unaryExpr(op, operand, _) where op == .unaryPlus || op == .unaryMinus:
                    if case .intLiteral = ast.arena.expr(operand) {
                        expectedTypeOverrides[argument] = specializedType
                    }
                default: break
                }
            }
        }

        var inferredNonLambdaArgTypes = preInferredNonLambdaArgTypes
        var lambdaLiteralIndices: Set<Int> = []
        var inputOnlyLambdaIndices: Set<Int> = []
        var blockedLambdaRefinement = false
        var hasUnresolvableImplicitLambdaParameter = false
        var contextualArgExpectedTypes = [TypeID?](repeating: nil, count: args.count)
        var discardedExpectedTypeHintIndices: Set<Int> = []

        for (index, argument) in args.enumerated() {
            guard let argumentExpr = ast.arena.expr(argument.expr) else {
                continue
            }
            // Anonymous functions are blocks around a synthetic local function
            // and callable reference. Defer them like callable references so
            // their declaration body is first checked with the parameter type.
            if ast.arena.isAnonymousFunction(argument.expr) {
                continue
            }
            switch argumentExpr {
            case .lambdaLiteral:
                lambdaLiteralIndices.insert(index)
            case .callableRef:
                break
            case .intLiteral:
                // Always re-infer an unsuffixed int literal against the surviving
                // candidates' parameter type, even if a previous pass already gave
                // it a default Int. This lets member calls like
                // `shortArray.binarySearch(20)` narrow to Short/Byte.
                let literalExpectedType = uniformNumericLiteralParameterType(
                    at: index,
                    argumentLabel: argument.label,
                    candidates: candidates,
                    sema: sema
                )
                inferredNonLambdaArgTypes[index] = driver.inferExpr(
                    argument.expr, ctx: ctx, locals: &locals, expectedType: literalExpectedType
                )
            case .uintLiteral:
                // Contextualize suffixed unsigned literals too. Kotlin narrows
                // constants such as 1u to UByte/UShort parameters when the value
                // fits, which is needed by source-backed unsigned extensions.
                let literalExpectedType = uniformUnsignedLiteralParameterType(
                    at: index,
                    argumentLabel: argument.label,
                    candidates: candidates,
                    sema: sema
                )
                inferredNonLambdaArgTypes[index] = driver.inferExpr(
                    argument.expr, ctx: ctx, locals: &locals, expectedType: literalExpectedType
                )
            case .unaryExpr(let op, let operandID, _):
                guard (op == .unaryPlus || op == .unaryMinus),
                      case .intLiteral = ast.arena.expr(operandID)
                else {
                    if inferredNonLambdaArgTypes[index] == nil {
                        inferredNonLambdaArgTypes[index] = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
                    }
                    continue
                }
                // Constant-folded unary +/- over an int literal should see the
                // candidates' parameter type, just like a bare int literal, so
                // `byteArrayOf(1, -1)` and `shortArrayOf(1, -1)` resolve.
                let literalExpectedType = uniformNumericLiteralParameterType(
                    at: index,
                    argumentLabel: argument.label,
                    candidates: candidates,
                    sema: sema
                )
                inferredNonLambdaArgTypes[index] = driver.inferExpr(
                    argument.expr, ctx: ctx, locals: &locals, expectedType: literalExpectedType
                )
            default:
                if let expectedType = expectedTypeOverrides[index],
                   isInferableNestedCallExpr(argument.expr, ast: ast)
                {
                    let diagnosticsCheckpoint = sema.diagnostics.checkpoint()
                    var contextualLocals = locals
                    var contextualContext = ctx
                    if expectedTypeHintIndices.contains(index) {
                        contextualContext.validatesLiftedHintCollectionArguments = true
                    }
                    let contextualType = driver.inferExpr(
                        argument.expr,
                        ctx: contextualContext,
                        locals: &contextualLocals,
                        expectedType: expectedType
                    )
                    let emittedError = sema.diagnostics.diagnostics.dropFirst(diagnosticsCheckpoint).contains {
                        $0.severity == .error
                    }
                    // A lifted covariant result supplies a hint, not an exact
                    // argument requirement. A fixed Box<Int> factory can fail
                    // against Box<Any> while still satisfying the outer Base<Any>.
                    if expectedTypeHintIndices.contains(index),
                       contextualType == sema.types.errorType || emittedError {
                        sema.diagnostics.rollback(to: diagnosticsCheckpoint)
                        discardedExpectedTypeHintIndices.insert(index)
                        inferredNonLambdaArgTypes[index] = driver.inferExpr(
                            argument.expr, ctx: ctx, locals: &locals
                        )
                        continue
                    }
                    locals = contextualLocals
                    if contextualType != sema.types.errorType,
                       !emittedError,
                       let argumentRange = ast.arena.exprRange(argument.expr)
                    {
                        sema.diagnostics.removeErrorDiagnostics(containedIn: argumentRange)
                    }
                    inferredNonLambdaArgTypes[index] = contextualType
                    continue
                }
                if inferredNonLambdaArgTypes[index] != nil {
                    continue
                }
                inferredNonLambdaArgTypes[index] = driver.inferExpr(
                    argument.expr, ctx: ctx, locals: &locals,
                    expectedType: expectedTypeOverrides[index]
                )
            }
        }

        // Class-name values must denote their companions before they constrain
        // receiver lambdas, e.g. the block in `with(Duration) { ... }`.
        for (index, argument) in args.enumerated() {
            if let type = inferredNonLambdaArgTypes[index],
               let companionType = driver.helpers.retypeClassNameAsCompanionValue(
                   argument.expr, currentType: type, ast: ast, sema: sema
               )
            {
                inferredNonLambdaArgTypes[index] = companionType
            }
        }

        for (index, argument) in args.enumerated() {
            if let type = inferredNonLambdaArgTypes[index] {
                inferredNonLambdaArgTypes[index] = sourceLevelRangeArgumentType(
                    argument.expr, inferredType: type, ctx: ctx
                )
            }
        }

        if lambdaLiteralIndices.count > 1 {
            blockedLambdaRefinement = true
        }

        // Resolve source function returns only after header-based argument
        // pruning, so an inapplicable same-named overload cannot look recursive.
        if candidates.contains(where: {
            driver.inferredReturnFunctions[$0] != nil
                && !driver.checkedInferredReturnFunctions.contains($0)
        }) {
            let narrowed = narrowedCallCandidates(
                candidates: candidates,
                args: args,
                callRange: callRange,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                receiverType: receiverType,
                boundObjectDispatchReceiverCandidates: boundObjectDispatchReceiverCandidates,
                ctx: ctx
            )
            if narrowed.count == 1 {
                driver.inferFunctionReturnTypesIfNeeded(for: narrowed)
            }
        }

        // Each argument's expected type is computed and applied before moving to
        // the next one, so an already-inferred lambda constrains the arguments
        // that follow it: in `fold({ k, e -> ... }, { k, acc, e -> ... })` the
        // accumulator type is only pinned down by the first lambda's return type.
        var argTypes = [TypeID](repeating: sema.types.errorType, count: args.count)
        for (index, argument) in args.enumerated() {
            defer { ctx.dataFlow.localStability.inPlaceLambdaScopes.remove(argument.expr) }
            if let override = expectedTypeOverrides[index],
               !discardedExpectedTypeHintIndices.contains(index) {
                contextualArgExpectedTypes[index] = override
            } else if let argumentExpr = ast.arena.expr(argument.expr) {
                let narrowedCandidates = narrowedCallCandidates(
                    candidates: candidates,
                    args: args,
                    callRange: callRange,
                    inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                    receiverType: receiverType,
                    boundObjectDispatchReceiverCandidates: boundObjectDispatchReceiverCandidates,
                    ctx: ctx
                )
                let expectedTypeCandidates = narrowedCandidates.isEmpty ? candidates : narrowedCandidates

                switch argumentExpr {
                case .intLiteral:
                    contextualArgExpectedTypes[index] = uniformNumericLiteralParameterType(
                        at: index,
                        argumentLabel: argument.label,
                        candidates: expectedTypeCandidates,
                        sema: sema
                    )
                case .uintLiteral:
                    contextualArgExpectedTypes[index] = uniformUnsignedLiteralParameterType(
                        at: index,
                        argumentLabel: argument.label,
                        candidates: expectedTypeCandidates,
                        sema: sema
                    )
                case .unaryExpr(let op, let operandID, _):
                    if (op == .unaryPlus || op == .unaryMinus),
                       case .intLiteral = ast.arena.expr(operandID)
                    {
                        contextualArgExpectedTypes[index] = uniformNumericLiteralParameterType(
                            at: index,
                            argumentLabel: argument.label,
                            candidates: expectedTypeCandidates,
                            sema: sema
                        )
                    }
                case .callableRef:
                    // Keep the reference's concrete return type for final call
                    // inference; the outer result is only an upper constraint.
                    contextualArgExpectedTypes[index] = contextualCallableReferenceArgumentType(
                        at: index,
                        argumentLabel: argument.label,
                        args: args,
                        callRange: callRange,
                        expectedCandidates: expectedTypeCandidates,
                        callCandidates: candidates,
                        explicitTypeArgs: explicitTypeArgs,
                        receiverType: receiverType,
                        inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                        callResultType: nil,
                        resolver: ctx.resolver,
                        ctx: ctx
                    )
                case .blockExpr where ast.arena.isAnonymousFunction(argument.expr):
                    contextualArgExpectedTypes[index] = contextualCallableReferenceArgumentType(
                        at: index,
                        argumentLabel: argument.label,
                        args: args,
                        callRange: callRange,
                        expectedCandidates: expectedTypeCandidates,
                        callCandidates: candidates,
                        explicitTypeArgs: explicitTypeArgs,
                        receiverType: receiverType,
                        inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                        callResultType: contextualCallResultType,
                        resolver: ctx.resolver,
                        ctx: ctx
                    )
                case .ifExpr:
                    contextualArgExpectedTypes[index] = uniformContextualParameterType(
                        for: argument,
                        at: index,
                        candidates: expectedTypeCandidates,
                        ctx: ctx
                    )
                case let .binary(op, _, _, _) where op == .elvis:
                    // Elvis branches need the candidate parameter type, e.g.
                    // `resumeWith(throwable?.let { Result.failure(it) } ?: RESUME)`
                    // where `Result.failure`'s return-only `T` is only
                    // determinable from `resumeWith`'s `Result<T>` parameter.
                    contextualArgExpectedTypes[index] = uniformContextualParameterType(
                        for: argument,
                        at: index,
                        candidates: expectedTypeCandidates,
                        receiverType: receiverType ?? ctx.implicitReceiverType,
                        ctx: ctx
                    )
                case let .lambdaLiteral(lambdaParams, _, _, _):
                    // Prove non-escaping invocation before checking the lambda body.
                    if !expectedTypeCandidates.isEmpty, expectedTypeCandidates.allSatisfy({ candidate in
                        guard let signature = sema.symbols.functionSignature(for: candidate),
                              argument.label != nil || signature.parameterTypes.count == args.count,
                              let parameterIndex = parameterIndexForCallArgument(
                                  at: index, label: argument.label, in: signature, sema: sema
                              )
                        else { return false }
                        return ctx.dataFlow.localStability.isInPlaceParameter(
                            parameterIndex, function: candidate, sema: sema
                        )
                    }) {
                        ctx.dataFlow.localStability.inPlaceLambdaScopes.insert(argument.expr)
                    }
                    let expectation = lambdaLiteralExpectedType(
                        at: index,
                        args: args,
                        callRange: callRange,
                        candidates: expectedTypeCandidates,
                        explicitTypeArgs: explicitTypeArgs,
                        receiverType: receiverType,
                        inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                        resolver: ctx.resolver,
                        sema: sema,
                        ctx: ctx
                    )
                    // For a generic scope function such as `T.let(block: (T) -> R): R`,
                    // the expected call result fixes R before the lambda body is
                    // inferred. Keep the receiver-derived T in the expected lambda
                    // while replacing only its matching return type parameter.
                    // Use the same narrowed candidates that supplied the lambda shape:
                    // an inapplicable unqualified extension must not hide this context.
                    let contextualLambdaType = contextualCallableArgumentType(
                        expectation.type, callResultType: contextualCallResultType,
                        candidates: expectedTypeCandidates,
                        argumentIndex: index,
                        argumentLabel: argument.label,
                        args: args,
                        inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                        sema: sema
                    )
                    contextualArgExpectedTypes[index] = contextualLambdaType
                    if let contextualLambdaType, expectedTypeCandidates.count == 1,
                       let candidate = expectedTypeCandidates.first,
                       let signature = sema.symbols.functionSignature(for: candidate)
                    {
                        contextualArgExpectedTypes[index] = applyDispatchReceiverClassTypeArgs(
                            to: contextualLambdaType, signature: signature, candidate: candidate, ctx: ctx
                        )
                    }
                    if declaresConcreteLambdaParameterTypes(
                        at: index,
                        args: args,
                        callRange: callRange,
                        candidates: expectedTypeCandidates,
                        sema: sema,
                        ctx: ctx
                    ) {
                        sema.bindings.markSourceDeclaredExpectedType(argument.expr)
                    }
                    if expectation.isInputOnly {
                        inputOnlyLambdaIndices.insert(index)
                    }
                    if expectation.blocksRefinement {
                        blockedLambdaRefinement = true
                        // A lambda with no declared parameter list (`{ it }` or `{ ... }`)
                        // has no locally-known type to fall back on; if the surviving
                        // candidates each want exactly one parameter but disagree on its
                        // type, there is no way to check the body without guessing which
                        // overload was meant.
                        if lambdaParams.isEmpty,
                           expectation.hasAmbiguousImplicitParameterShape,
                           lambdaBodyUsesImplicitIt(argument.expr, ctx: ctx)
                        {
                            hasUnresolvableImplicitLambdaParameter = true
                        }
                    }
                default:
                    break
                }
            }

            if let contextualExpectedType = contextualArgExpectedTypes[index] {
                var inferenceContext = lambdaContextOverrides[index] ?? ctx
                let isCallableReferenceArgument: Bool = {
                    if case .callableRef = ast.arena.expr(argument.expr) { return true }
                    return ast.arena.isAnonymousFunction(argument.expr)
                }()
                if isCallableReferenceArgument {
                    inferenceContext.isCallableReferenceArgument = true
                    let parameters = candidates.flatMap { candidate -> [SymbolID] in
                        guard let signature = sema.symbols.functionSignature(for: candidate) else { return [] }
                        return Array(signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount))
                    }
                    inferenceContext.callableReferenceInferenceParameters.formUnion(parameters)
                    inferenceContext.callableReferenceInferenceParameters.subtract(
                        driver.helpers.lexicalTypeParameterSymbols(in: ctx)
                    )
                }
                if expectedTypeHintIndices.contains(index) {
                    inferenceContext.validatesLiftedHintCollectionArguments = true
                }
                let checkpoint = sema.diagnostics.checkpoint()
                var contextualLocals = locals
                var inferredType = driver.inferExpr(
                    argument.expr,
                    ctx: inferenceContext,
                    locals: &contextualLocals,
                    expectedType: contextualExpectedType
                )
                let emittedError = sema.diagnostics.diagnostics.dropFirst(checkpoint).contains {
                    $0.severity == .error
                }
                if expectedTypeHintIndices.contains(index),
                   inferredType == sema.types.errorType || emittedError {
                    sema.diagnostics.rollback(to: checkpoint)
                    inferredType = driver.inferExpr(argument.expr, ctx: inferenceContext, locals: &locals)
                    inputOnlyLambdaIndices.remove(index)
                } else {
                    locals = contextualLocals
                }
                if inputOnlyLambdaIndices.contains(index) {
                    argTypes[index] = rebuildLambdaLiteralType(
                        exprID: argument.expr,
                        inferredType: inferredType,
                        contextualExpectedType: contextualExpectedType,
                        sema: sema
                    )
                } else {
                    argTypes[index] = inferredType
                }
            } else if let cached = inferredNonLambdaArgTypes[index] {
                argTypes[index] = cached
            } else {
                argTypes[index] = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
            }
            argTypes[index] = sourceLevelRangeArgumentType(
                argument.expr, inferredType: argTypes[index], ctx: ctx
            )
            inferredNonLambdaArgTypes[index] = argTypes[index]
        }

        let refinedArgTypes = args.enumerated().map { index, argument -> TypeID in
            // Infer generic SAM arguments from the lambda's actual function
            // inputs, rather than its provisional interface containing free T.
            if lambdaLiteralIndices.contains(index),
               case .classType = sema.types.kind(of: argTypes[index]),
               sema.bindings.isSamConversion(argument.expr),
               let functionType = sema.bindings.samUnderlyingFunctionType(for: argument.expr) {
                return functionType
            }
            if let samLambda = samConstructorLambdaArgument(argument.expr, ctx: ctx),
               let functionType = sema.bindings.samUnderlyingFunctionType(for: samLambda) {
                return functionType
            }
            let type = argTypes[index]
            // A bare `ClassName` argument denotes the class's companion object.
            if !lambdaLiteralIndices.contains(index),
               let companionType = driver.helpers.retypeClassNameAsCompanionValue(
                   argument.expr, currentType: type, ast: ast, sema: sema
               )
            {
                return companionType
            }
            return type
        }

        return PreparedCallArguments(
            argTypes: collectPostponedArgumentConstraints(
                args: args, range: callRange, argTypes: refinedArgTypes, candidates: candidates,
                receiverType: receiverType, ctx: ctx
            ),
            lambdaLiteralIndices: lambdaLiteralIndices,
            inputOnlyLambdaIndices: inputOnlyLambdaIndices,
            blockedLambdaRefinement: blockedLambdaRefinement,
            hasUnresolvableImplicitLambdaParameter: hasUnresolvableImplicitLambdaParameter
        )
    }

    func resolveCallRespectingLambdaReturnType(
        candidates: [SymbolID],
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        calleeName: InternedString,
        explicitTypeArgs: [TypeID],
        typeAliasConstructor: TypeAliasConstructorContext? = nil,
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
        bindsObjectDispatchReceiver: Bool = false,
        additionalDispatchReceiverTypes: [TypeID] = [],
        additionalBoundObjectDispatchReceiverCandidates: Set<SymbolID> = [],
        candidateArgumentTypes: [SymbolID: [Int: TypeID]] = [:],
        lambdaLiteralIndices: Set<Int>,
        inputOnlyLambdaIndices: Set<Int>,
        blockedLambdaRefinement: Bool,
        hasUnresolvableImplicitLambdaParameter: Bool,
        ctx: TypeInferenceContext
    ) -> ResolvedCall {
        let resolvedArgs = zip(args, argTypes).map { argument, type in
            let literal = integerArgumentValues(argument.expr, ctx: ctx)
            return CallArg.source(
                argument, type: type, callRange: range, ast: ctx.ast,
                signedIntegerLiteral: literal.signed,
                unsignedIntegerLiteral: literal.unsigned
            )
        }
        let call = CallExpr(
            range: range,
            calleeName: calleeName,
            args: resolvedArgs,
            explicitTypeArgs: explicitTypeArgs,
            dispatchReceiverTypes: additionalDispatchReceiverTypes + (bindsObjectDispatchReceiver
                ? importedObjectDispatchReceiverTypes(named: calleeName, candidates: candidates, ctx: ctx)
                : []) + ctx.implicitReceiverMemberLookupEntries().map(\.type),
            boundObjectDispatchReceiverCandidates: additionalBoundObjectDispatchReceiverCandidates.union(
                bindsObjectDispatchReceiver
                ? importedObjectDispatchReceiverCandidates(named: calleeName, candidates: candidates, ctx: ctx)
                : []
            ),
            typeAliasConstructor: typeAliasConstructor,
            elvisLhsExpectedTypeHint: ctx.isElvisBranchExpectedTypeHint,
            elvisRhsCallResultTypeHint: ctx.elvisRhsCallResultTypeHint
        )

        if candidates.contains(where: {
            driver.inferredReturnFunctions[$0] != nil
                && !driver.checkedInferredReturnFunctions.contains($0)
        }) {
            // Select by receiver and arguments before inferring a return. An
            // unselected overload must not introduce a false dependency cycle.
            let selection = ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: nil,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                resultIsDiscarded: ctx.isCallResultDiscarded,
                ctx: ctx.sema
            )
            if selection.diagnostic == nil, let chosen = selection.chosenCallee {
                driver.inferFunctionReturnTypesIfNeeded(for: [chosen])
            }
        }

        let hasRefinementAnnotation = candidates.contains(where: {
            hasOverloadResolutionByLambdaReturnTypeAnnotation(symbol: $0, sema: ctx.sema)
        })
        let functionParameterArgumentPositions = Set(args.indices.filter { argIndex in
            candidates.contains { candidate in
                guard let signature = ctx.sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                let parameterType: TypeID?
                if lambdaLiteralIndices.contains(argIndex) {
                    parameterType = lambdaParameterTypeForArgument(
                        at: argIndex,
                        args: args,
                        callRange: range,
                        in: signature,
                        ctx: ctx
                    )
                } else {
                    parameterType = parameterTypeForArgument(at: argIndex, in: signature)
                }
                guard let parameterType else { return false }
                if case .functionType = ctx.sema.types.kind(of: parameterType) {
                    return true
                }
                return false
            }
        })
        let functionTypedArgumentIndices = Set(args.indices.filter { index in
            guard case .functionType = ctx.sema.types.kind(of: argTypes[index]) else {
                return false
            }
            guard let expr = ctx.ast.arena.expr(args[index].expr) else {
                return false
            }
            if case .callableRef = expr {
                return false
            }
            return true
        })

        if blockedLambdaRefinement, hasRefinementAnnotation || hasUnresolvableImplicitLambdaParameter {
            return ambiguousCallResult(range: range, candidateSymbols: candidates, sema: ctx.sema)
        }

        let contextualExpectedType = overloadResolutionExpectedType(from: expectedType, sema: ctx.sema)

        guard !inputOnlyLambdaIndices.isEmpty else {
            let resolved = ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: contextualExpectedType,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                resultIsDiscarded: ctx.isCallResultDiscarded,
                ctx: ctx.sema
            )
            return validateConstructorTypeInference(
                resolved, args: args, argTypes: argTypes, explicitTypeArgs: explicitTypeArgs,
                expectedType: contextualExpectedType, range: range, ctx: ctx
            )
        }

        // These ambiguity checks only apply when lambda-return-type overload
        // resolution is actually attempted (inputOnlyLambdaIndices is non-empty).
        // Running them earlier would incorrectly reject single-candidate calls.
        if functionParameterArgumentPositions.count > 1, hasRefinementAnnotation {
            return ambiguousCallResult(range: range, candidateSymbols: candidates, sema: ctx.sema)
        }
        if functionTypedArgumentIndices.count > 1, hasRefinementAnnotation {
            return ambiguousCallResult(range: range, candidateSymbols: candidates, sema: ctx.sema)
        }

        let overloadResolutionExpectedType: TypeID? = nil

        let probe = ctx.resolver.probeCall(
            candidates: candidates,
            call: call,
            expectedType: overloadResolutionExpectedType,
            implicitReceiverType: implicitReceiverType,
            candidateArgumentTypes: candidateArgumentTypes,
            ignoringLambdaReturnTypeArgumentIndices: inputOnlyLambdaIndices,
            resultIsDiscarded: ctx.isCallResultDiscarded,
            ctx: ctx.sema
        )
        let viableSymbols = probe.viableCandidates.map(\.symbol)
        if viableSymbols.isEmpty {
            return ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                resultIsDiscarded: ctx.isCallResultDiscarded,
                ctx: ctx.sema
            )
        }
        if viableSymbols.count == 1 {
            return ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                resultIsDiscarded: ctx.isCallResultDiscarded,
                ctx: ctx.sema
            )
        }
        guard lambdaLiteralIndices.count == 1,
              let lambdaIndex = lambdaLiteralIndices.first,
              inputOnlyLambdaIndices.contains(lambdaIndex)
        else {
            return ambiguousCallResult(range: range, candidateSymbols: viableSymbols, sema: ctx.sema)
        }
        // When all viable candidates share the same input-only HOF shape, the
        // apparent ambiguity is structural — not semantic. Fall back to the standard
        // resolver which picks the most specific receiver type.
        if viableSymbols.allSatisfy({
            Self.inputOnlyExternalLinkNames.contains(ctx.sema.symbols.externalLinkName(for: $0) ?? "")
        }) {
            return ctx.resolver.resolveCall(
                candidates: viableSymbols,
                call: call,
                expectedType: contextualExpectedType,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                resultIsDiscarded: ctx.isCallResultDiscarded,
                ctx: ctx.sema
            )
        }
        guard viableSymbols.contains(where: {
            hasOverloadResolutionByLambdaReturnTypeAnnotation(symbol: $0, sema: ctx.sema)
        }) else {
            return ambiguousCallResult(range: range, candidateSymbols: viableSymbols, sema: ctx.sema)
        }

        let refinedCandidates = refineCandidatesByLambdaReturnType(
            candidateSymbols: viableSymbols,
            lambdaArgumentIndex: lambdaIndex,
            argType: argTypes[lambdaIndex],
            args: args,
            callRange: range,
            sema: ctx.sema,
            ctx: ctx
        )
        if refinedCandidates.isEmpty {
            return ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                resultIsDiscarded: ctx.isCallResultDiscarded,
                ctx: ctx.sema
            )
        }
        if refinedCandidates.count == 1 {
            return ctx.resolver.resolveCall(
                candidates: refinedCandidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                resultIsDiscarded: ctx.isCallResultDiscarded,
                ctx: ctx.sema
            )
        }
        return ambiguousCallResult(range: range, candidateSymbols: refinedCandidates, sema: ctx.sema)
    }

    func overloadResolutionExpectedType(from expectedType: TypeID?, sema: SemaModule) -> TypeID? {
        // Unit contexts accept and discard any expression result, so Unit must
        // not act as a return-type constraint while choosing an overload.
        guard expectedType != sema.types.unitType else {
            return nil
        }
        return expectedType
    }

    func narrowedCallCandidates(
        candidates: [SymbolID],
        args: [CallArgument],
        callRange: SourceRange,
        inferredNonLambdaArgTypes: [Int: TypeID],
        receiverType: TypeID?,
        boundObjectDispatchReceiverCandidates: Set<SymbolID> = [],
        forImplicitMemberApplicability: Bool = false,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema

        func boundObjectReceiverType(for candidate: SymbolID) -> TypeID? {
            guard boundObjectDispatchReceiverCandidates.contains(candidate),
                  sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
                  let owner = sema.symbols.parentSymbol(for: candidate),
                  let ownerKind = sema.symbols.symbol(owner)?.kind,
                  ownerKind == .class || ownerKind == .interface || ownerKind == .object
            else { return nil }
            if let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
               case let .classType(receiverClass) = sema.types.kind(of: receiver),
               receiverClass.classSymbol == owner
            {
                return receiver
            }
            guard ownerKind == .object else { return nil }
            return sema.types.make(.classType(ClassType(
                classSymbol: owner,
                args: [],
                nullability: .nonNull
            )))
        }

        // Except for bound object members, a candidate that declares an
        // extension/member receiver cannot be chosen without an explicit or
        // implicit receiver -- buildReceiverConstraints rejects it
        // outright in that case. Without pruning it here too, an unqualified
        // call such as `measureTimedValue { ... }` still sees an unrelated
        // same-named extension (e.g. `TimeSource.measureTimedValue`) as a live
        // candidate for the lambda's expected type, corrupting it even though
        // that extension can never actually be selected. A present-but-
        // mismatched receiver is left to final resolution, unchanged.
        let effectiveReceiverType = receiverType ?? ctx.implicitReceiverType
        let candidates = effectiveReceiverType != nil
            ? candidates
            : candidates.filter {
                sema.symbols.symbol($0)?.kind == .constructor
                    || sema.symbols.functionSignature(for: $0)?.receiverType == nil
                    || boundObjectReceiverType(for: $0) != nil
            }

        var narrowed = candidates.filter { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  isCallableArityCompatible(signature: signature, argCount: args.count),
                  let parameterMapping = parameterMappingForCallArguments(args, in: signature, callRange: callRange, ctx: ctx)
            else {
                return false
            }
            for (otherIndex, inferredType) in inferredNonLambdaArgTypes {
                guard args.indices.contains(otherIndex),
                      let parameterIndex = parameterMapping[otherIndex],
                      let parameterType = contextualCallArgumentType(
                          args[otherIndex],
                          parameterIndex: parameterIndex,
                          in: signature,
                          ctx: ctx
                      )
                else {
                    return false
                }
                let isNamedVarargArray = args[otherIndex].label != nil
                    && signature.valueParameterIsVararg.indices.contains(parameterIndex)
                    && signature.valueParameterIsVararg[parameterIndex]
                if args[otherIndex].isSpread || isNamedVarargArray {
                    // The final resolver checks the array shape and, for
                    // generic arrays, constrains the vararg element type.
                    // Comparing this array with the element parameter here
                    // prematurely prunes every viable candidate.
                    continue
                }
                if sema.types.isSubtype(inferredType, parameterType) {
                    continue
                }
                if !args[otherIndex].isSpread,
                   integerLiteralFitsParameter(args[otherIndex].expr, parameterType: parameterType, ctx: ctx)
                {
                    continue
                }
                // SAM conversion can make a function value applicable even
                // without a nominal subtype relation. Early tower selection
                // must leave that decision to contextual argument inference.
                if forImplicitMemberApplicability,
                   isFunctionTypeLike(inferredType, sema: sema),
                   driver.helpers.samFunctionType(for: parameterType, sema: sema) != nil
                {
                    continue
                }
                // A parameter whose type is still an unsubstituted type
                // parameter (`initialValue: R`) never passes a subtype check
                // before inference runs, so judge those positions by shape:
                // reject incompatible function or nominal type shapes.
                guard typeMentionsTypeParameter(parameterType, sema: sema) else {
                    return false
                }
                if case .functionType = sema.types.kind(of: sema.types.makeNonNullable(parameterType)),
                   !isFunctionTypeLike(inferredType, sema: sema)
                {
                    return false
                }
                if !args[otherIndex].isSpread,
                   case let .classType(parameterClass) = sema.types.kind(of: parameterType),
                   case let .classType(argumentClass) = sema.types.kind(of: inferredType),
                   !sema.types.isNominalSubtypeSymbol(argumentClass.classSymbol, of: parameterClass.classSymbol)
                {
                    return false
                }
            }
            // Overloads that differ only in the arity of a function-typed
            // parameter (Grouping.fold's initialValue vs. initialValueSelector
            // forms) can be told apart before inference when the lambda spells
            // out its parameters: a `{ a, b -> ... }` argument can only match a
            // two-parameter function type. Without this the surviving
            // candidates disagree on the lambda's shape and no expected type is
            // pushed into the body, leaving its parameters untyped.
            for (argIndex, argument) in args.enumerated() where !forImplicitMemberApplicability {
                guard case let .lambdaLiteral(lambdaParams, _, _, _) = ctx.ast.arena.expr(argument.expr)
                else {
                    continue
                }
                guard let parameterType = lambdaParameterTypeForArgument(
                        at: argIndex,
                        args: args,
                        callRange: callRange,
                        in: signature,
                        ctx: ctx
                    ),
                      case let .functionType(functionType) = sema.types.kind(
                          of: sema.types.makeNonNullable(parameterType)
                      )
                else {
                    if !lambdaParams.isEmpty {
                        return false
                    }
                    continue
                }
                // Without a parameter list, only zero parameters or a single
                // implicit `it` can be supplied, never two or more.
                if lambdaParams.isEmpty {
                    if functionType.params.count > 1 {
                        return false
                    }
                } else if functionType.params.count != lambdaParams.count {
                    return false
                }
            }
            return true
        }

        // Prune candidates whose declared receiver the call-site receiver can
        // never satisfy: `onEach` is declared on `Sequence`, `Iterable`,
        // `Map`, and `CharSequence`, but a `String` receiver can only ever
        // select the `CharSequence` overload. Infeasible siblings still go
        // through final resolution unchanged — leaving them in this set only
        // corrupts the lambda's expected type with irreconcilable parameter
        // shapes and leaves implicit `it` untyped.
        let receiverFeasible = narrowed.filter { candidate in
            if sema.symbols.symbol(candidate)?.kind == .constructor {
                return true
            }
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return receiverConstraintIsFeasible(
                signature: signature,
                receiverType: boundObjectReceiverType(for: candidate) ?? effectiveReceiverType,
                sema: sema
            )
        }
        narrowed = receiverFeasible.isEmpty ? narrowed : receiverFeasible

        // Contextualization normally restores the original candidates when
        // pruning found none. Tower applicability needs the actual empty set,
        // and must defer every lambda-body preference to the selected tier.
        if forImplicitMemberApplicability {
            return narrowed
        }

        // A bare lambda literal is itself a function value. When overloads
        // differ between a function-typed parameter and an unconstrained type
        // parameter at the same position, prefer the function-typed candidates
        // so the lambda receives a single contextual type. Otherwise a generic
        // overload can also bind its type parameter to the lambda's function
        // type, leaving equivalent candidates and untyped `it` parameters in
        // later lambdas. This is a general shape rule, not a stdlib-name rule.
        let emptyLambdaIndices = args.indices.filter { argIndex in
            guard case let .lambdaLiteral(lambdaParams, _, _, _) = ctx.ast.arena.expr(args[argIndex].expr),
                  lambdaParams.isEmpty
            else {
                return false
            }
            return true
        }
        let lambdaShapeIndices = emptyLambdaIndices.filter { argIndex in
            let hasFunctionCandidate = narrowed.contains { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      let parameterType = lambdaParameterTypeForArgument(
                              at: argIndex,
                              args: args,
                              callRange: callRange,
                              in: signature,
                              ctx: ctx
                          )
                else {
                    return false
                }
                return isFunctionTypeLike(parameterType, sema: sema)
            }
            let hasNonFunctionCandidate = narrowed.contains { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      let parameterType = lambdaParameterTypeForArgument(
                              at: argIndex,
                              args: args,
                              callRange: callRange,
                              in: signature,
                              ctx: ctx
                          )
                else {
                    return false
                }
                return !isFunctionTypeLike(parameterType, sema: sema)
            }
            return hasFunctionCandidate && hasNonFunctionCandidate
        }
        let lambdaShapeNarrowed = narrowed.filter { candidate in
            lambdaShapeIndices.allSatisfy { argIndex in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      let parameterType = lambdaParameterTypeForArgument(
                              at: argIndex,
                              args: args,
                              callRange: callRange,
                              in: signature,
                              ctx: ctx
                          )
                else {
                    return false
                }
                return isFunctionTypeLike(parameterType, sema: sema)
            }
        }
        if !lambdaShapeNarrowed.isEmpty,
           lambdaShapeNarrowed.count < narrowed.count
        {
            return lambdaShapeNarrowed
        }

        // A null-only producer has no non-null lower bound from which the
        // generic `() -> T?` overload can infer T. Kotlin resolves this case
        // through the bottom-type overload, but that overload must not win for
        // ordinary producers such as `{ 42 }`.
        let nullOnlyLambdaIndices = emptyLambdaIndices.filter { argIndex in
            lambdaBodyIsNullLiteral(args[argIndex].expr, ctx: ctx)
        }
        let nullProducerNarrowed = narrowed.filter { candidate in
            nullOnlyLambdaIndices.allSatisfy { argIndex in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      let parameterType = lambdaParameterTypeForArgument(
                              at: argIndex,
                              args: args,
                              callRange: callRange,
                              in: signature,
                              ctx: ctx
                          ),
                      case let .functionType(functionType) = sema.types.kind(
                          of: sema.types.makeNonNullable(parameterType)
                      )
                else {
                    return false
                }
                return functionType.returnType == sema.types.nullableNothingType
            }
        }
        if !nullOnlyLambdaIndices.isEmpty,
           !nullProducerNarrowed.isEmpty,
           nullProducerNarrowed.count < narrowed.count
        {
            return nullProducerNarrowed
        }

        return narrowed.isEmpty ? candidates : narrowed
    }

    /// Used only to keep the lambda expected-type candidate set free
    /// of same-named overloads that final resolution could never select.
    private func receiverConstraintIsFeasible(
        signature: FunctionSignature,
        receiverType: TypeID?,
        sema: SemaModule
    ) -> Bool {
        guard let receiverType,
              let declaredReceiver = signature.receiverType
        else {
            return true
        }
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        let nonNullDeclared = sema.types.makeNonNullable(declaredReceiver)
        if case let .typeParam(receiverTypeParam) = sema.types.kind(of: nonNullDeclared) {
            // Bare type-parameter receiver (`C : Iterable<T>`, `S : CharSequence`):
            // judge feasibility by the parameter's upper bounds after
            // substituting the receiver variable itself, so F-bounded contracts
            // (`T : Comparable<T>`) still hold. Bounds that stay type parameters
            // (`C : R`) constrain a different variable and are skipped.
            let signatureBounds: [TypeID]
            if let index = signature.typeParameterSymbols.firstIndex(of: receiverTypeParam.symbol),
               signature.typeParameterUpperBoundsList.indices.contains(index) {
                signatureBounds = signature.typeParameterUpperBoundsList[index]
            } else {
                signatureBounds = []
            }
            let symbolBounds = sema.symbols.typeParameterUpperBounds(for: receiverTypeParam.symbol)
            let bounds = signatureBounds + symbolBounds.filter { !signatureBounds.contains($0) }
            guard !bounds.isEmpty else {
                return true
            }
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            guard let typeVar = typeVarBySymbol[receiverTypeParam.symbol] else {
                return true
            }
            let substitution: [TypeVarID: TypeID] = [typeVar: nonNullReceiver]
            for bound in bounds {
                let substitutedBound = sema.types.substituteTypeParameters(
                    in: bound,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
                let nonNullBound = sema.types.makeNonNullable(substitutedBound)
                if case .typeParam = sema.types.kind(of: nonNullBound) {
                    continue
                }
                if let boundClass = resolveClassType(nonNullBound, sema: sema),
                   let actualClass = resolveClassType(nonNullReceiver, sema: sema)
                {
                    if actualClass.classSymbol != boundClass.classSymbol,
                       !sema.types.isNominalSubtypeSymbol(
                           actualClass.classSymbol,
                           of: boundClass.classSymbol
                       )
                    {
                        return false
                    }
                    continue
                }
                if !sema.types.isSubtype(nonNullReceiver, nonNullBound) {
                    return false
                }
            }
            return true
        }
        guard let declaredClass = resolveClassType(nonNullDeclared, sema: sema),
              let actualClass = resolveClassType(nonNullReceiver, sema: sema)
        else {
            // Non-nominal actual receiver (e.g. primitive String) or an opaque
            // declared receiver: fall back to the subtype oracle.
            return sema.types.isSubtype(nonNullReceiver, nonNullDeclared)
        }
        return declaredClass.classSymbol == actualClass.classSymbol
            || sema.types.isNominalSubtypeSymbol(
                actualClass.classSymbol,
                of: declaredClass.classSymbol
            )
    }

    /// Whether the only candidate for the call declares this argument as a
    /// function type whose parameter types are written out concretely in source
    /// (no type parameter left for inference to substitute). Such a signature
    /// is authoritative even where it says `Any`, unlike the `Any` inference
    /// falls back to when a type variable stays unsolved (BUG-163).
    private func declaresConcreteLambdaParameterTypes(
        at index: Int,
        args: [CallArgument],
        callRange: SourceRange,
        candidates: [SymbolID],
        sema: SemaModule,
        ctx: TypeInferenceContext
    ) -> Bool {
        guard candidates.count == 1,
              let candidate = candidates.first,
              sema.symbols.isSourceBackedSymbol(candidate),
              let signature = sema.symbols.functionSignature(for: candidate),
              let parameterType = lambdaParameterTypeForArgument(
                      at: index,
                      args: args,
                      callRange: callRange,
                      in: signature,
                      ctx: ctx
                  ),
              case let .functionType(declared) = sema.types.kind(of: parameterType)
        else {
            return false
        }
        return !declared.params.contains { typeMentionsTypeParameter($0, sema: sema) }
    }

    private func isFunctionTypeLike(_ type: TypeID, sema: SemaModule) -> Bool {
        if case .functionType = sema.types.kind(of: sema.types.makeNonNullable(type)) {
            return true
        }
        return driver.helpers.samFunctionType(for: type, sema: sema) != nil
    }

    private func rebuildLambdaLiteralType(
        exprID: ExprID,
        inferredType: TypeID,
        contextualExpectedType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        guard case let .lambdaLiteral(_, bodyExpr, _, _) = driver.ast.arena.expr(exprID),
              case let .functionType(functionType) = sema.types.kind(of: contextualExpectedType),
              let bodyType = sema.bindings.exprType(for: bodyExpr)
        else {
            return inferredType
        }

        return sema.types.make(.functionType(FunctionType(
            receiver: functionType.receiver,
            params: functionType.params,
            returnType: bodyType,
            isSuspend: functionType.isSuspend,
            nullability: functionType.nullability
        )))
    }

    private func refineCandidatesByLambdaReturnType(
        candidateSymbols: [SymbolID],
        lambdaArgumentIndex: Int,
        argType: TypeID,
        args: [CallArgument],
        callRange: SourceRange,
        sema: SemaModule,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        guard case let .functionType(argumentFunctionType) = sema.types.kind(of: argType) else {
            return candidateSymbols
        }

        return candidateSymbols.filter { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let parameterType = lambdaParameterTypeForArgument(
                          at: lambdaArgumentIndex,
                          args: args,
                          callRange: callRange,
                          in: signature,
                          ctx: ctx
                      ),
                  case let .functionType(parameterFunctionType) = sema.types.kind(of: parameterType)
            else {
                return false
            }
            return sema.types.isSubtype(argumentFunctionType.returnType, parameterFunctionType.returnType)
        }
    }

    private func hasOverloadResolutionByLambdaReturnTypeAnnotation(
        symbol: SymbolID,
        sema: SemaModule
    ) -> Bool {
        sema.symbols.annotations(for: symbol).contains { annotation in
            KnownCompilerAnnotation.overloadResolutionByLambdaReturnType.matches(annotation.annotationFQName)
        }
    }

    private func ambiguousCallResult(
        range: SourceRange,
        candidateSymbols: [SymbolID],
        sema: SemaModule
    ) -> ResolvedCall {
        ResolvedCall(
            chosenCallee: nil,
            substitutedTypeArguments: [:],
            parameterMapping: [:],
            diagnostic: Diagnostic(
                severity: .error,
                code: "KSWIFTK-SEMA-0003",
                message: "Ambiguous overload resolution.",
                primaryRange: range,
                secondaryRanges: sema.symbols.sortedDeclSites(of: candidateSymbols)
            )
        )
    }

    private func contextualCallableArgumentType(
        _ expectation: TypeID?,
        callResultType: TypeID?,
        candidates: [SymbolID],
        argumentIndex: Int? = nil,
        argumentLabel: InternedString? = nil,
        args: [CallArgument] = [],
        inferredNonLambdaArgTypes: [Int: TypeID] = [:],
        sema: SemaModule
    ) -> TypeID? {
        guard let callResultType,
              sema.types.makeNonNullable(callResultType) == callResultType,
              candidates.count == 1,
              let signature = sema.symbols.functionSignature(for: candidates[0]),
              sema.types.makeNonNullable(signature.returnType) == signature.returnType,
              case let .typeParam(resultParameter) = sema.types.kind(of: signature.returnType),
              let expectation, case let .functionType(function) = sema.types.kind(of: expectation),
              case let .typeParam(returnParameter) = sema.types.kind(of: function.returnType),
              returnParameter.symbol == resultParameter.symbol,
              !(function.params + function.contextReceivers + (function.receiver.map { [$0] } ?? [])).contains(where: {
                  sema.types.typeContainsTypeParam($0, symbol: resultParameter.symbol)
              })
        else { return expectation }
        // The discarded call result can guide a generic lambda result only
        // when the type parameter is not already constrained by another
        // argument. For example, `minOfWith(Comparator<Int>()) { ... }` must
        // keep the selector result as Int even when the whole call is coerced
        // to Unit by an enclosing lambda.
        if let argumentIndex,
           let lambdaParameterIndex = parameterIndexForCallArgument(
               at: argumentIndex, label: argumentLabel, in: signature, sema: sema
           )
        {
            for (otherIndex, inferredType) in inferredNonLambdaArgTypes
            where otherIndex != argumentIndex && inferredType != sema.types.errorType
            {
                guard args.indices.contains(otherIndex),
                      let otherParameterIndex = parameterIndexForCallArgument(
                          at: otherIndex,
                          label: args[otherIndex].label,
                          in: signature,
                          sema: sema
                      ),
                      otherParameterIndex != lambdaParameterIndex,
                      signature.parameterTypes.indices.contains(otherParameterIndex)
                else { continue }
                if sema.types.typeContainsTypeParam(
                    signature.parameterTypes[otherParameterIndex], symbol: resultParameter.symbol
                ) {
                    return expectation
                }
            }
        }
        // The call result is an upper constraint, not an equality. A broad
        // expected result must not replace a stricter declaration bound.
        var contextualResult = callResultType
        let parameterIndex = signature.typeParameterSymbols.firstIndex(of: resultParameter.symbol)
        let declaredBounds = parameterIndex.flatMap {
            $0 < signature.typeParameterUpperBoundsList.count ? signature.typeParameterUpperBoundsList[$0] : nil
        } ?? []
        let bounds = declaredBounds + sema.symbols.typeParameterUpperBounds(for: resultParameter.symbol)
            .filter { !declaredBounds.contains($0) }
        for bound in bounds where !sema.types.isSubtype(contextualResult, bound) {
            guard !sema.types.typeContainsAnyTypeParam(bound),
                  sema.types.isSubtype(bound, contextualResult) else { return expectation }
            contextualResult = bound
        }
        return sema.types.make(.functionType(FunctionType(
            contextReceivers: function.contextReceivers, receiver: function.receiver, params: function.params,
            returnType: returnParameter.nullability == .nullable ? sema.types.makeNullable(contextualResult) : contextualResult,
            isSuspend: function.isSuspend, nullability: function.nullability, throws: function.throws
        )))
    }

}
