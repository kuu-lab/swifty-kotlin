// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// Use a constructor's comparator parameter to type a nested compareBy
    /// selector even when unrelated constructor overloads have other parameter
    /// types. The normal shared-argument path requires every overload to agree.
    func prepareCompareByExpectedTypeOverrides(
        args: [CallArgument],
        callRange: SourceRange,
        candidates: [SymbolID],
        explicitTypeArgs: [TypeID],
        locals: LocalBindings,
        ctx: TypeInferenceContext,
        expectedTypeOverrides: inout [Int: TypeID]
    ) {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        guard let comparatorSymbol = sema.symbols.lookup(fqName: knownNames.kotlinComparatorFQName) else {
            return
        }

        for (argumentIndex, argument) in args.enumerated() {
            guard expectedTypeOverrides[argumentIndex] == nil,
                  case let .call(calleeID, typeArgs, _, _) = ast.arena.expr(argument.expr),
                  typeArgs.isEmpty,
                  case let .nameRef(nestedCalleeName, _) = ast.arena.expr(calleeID),
                  (nestedCalleeName == knownNames.compareBy || nestedCalleeName == knownNames.compareByDescending),
                  locals[nestedCalleeName] == nil,
                  sourceOrSyntheticStdlibFunctionSymbol(
                      nestedCalleeName,
                      fqComponents: ["kotlin", "comparisons", interner.resolve(nestedCalleeName)],
                      ctx: ctx
                  ) != nil
            else {
                continue
            }

            var comparatorParameterTypes: Set<TypeID> = []
            for candidate in candidates {
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      let parameterMapping = parameterMappingForCallArguments(
                          args, in: signature, callRange: callRange, ctx: ctx
                      ),
                      let parameterIndex = parameterMapping[argumentIndex],
                      let declaredParameterType = contextualCallArgumentType(
                          argument, parameterIndex: parameterIndex, in: signature, ctx: ctx
                      )
                else {
                    continue
                }

                let parameterType = sema.types.makeNonNullable(applyExplicitTypeArgs(
                    to: declaredParameterType,
                    signature: signature,
                    candidate: candidate,
                    explicitTypeArgs: explicitTypeArgs,
                    sema: sema
                ))
                guard case let .classType(classType) = sema.types.kind(of: parameterType),
                      classType.classSymbol == comparatorSymbol
                else {
                    continue
                }
                let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                guard !ctx.resolver.containsTypeVariable(
                    parameterType,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: sema.types
                )
                else {
                    continue
                }
                comparatorParameterTypes.insert(parameterType)
            }

            if comparatorParameterTypes.count == 1, let parameterType = comparatorParameterTypes.first {
                expectedTypeOverrides[argumentIndex] = parameterType
            }
        }
    }

    func inferMinMaxOfCall(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        // Primitive numeric minOf/maxOf fast path: only apply to the stdlib
        // comparison functions with value arguments; lambda/callable-ref
        // arguments (e.g. compareBy selectors or comparators) must go through
        // general overload resolution where an expected function type is
        // available, otherwise implicit `it` cannot be resolved.
        if let calleeName,
           calleeName == knownNames.maxOf || calleeName == knownNames.minOf,
           args.count == 2 || args.count == 3,
           !args.contains(where: { isLambdaOrCallableRefArg($0.expr, ast: ast) })
        {
            // Infer the first argument without an expected type to determine the overload.
            let firstArgType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: nil
            )

            let supportedNumericTypes = [
                sema.types.longType,
                sema.types.doubleType,
                sema.types.floatType,
                sema.types.intType,
            ] + (calleeName == knownNames.minOf ? [sema.types.byteType, sema.types.shortType] : [])
            if let resolvedParamType = primitiveMinMaxParameterType(
                args: args,
                firstArgType: firstArgType,
                supportedNumericTypes: supportedNumericTypes,
                ctx: ctx,
                locals: &locals
            ) {
                var shouldUsePrimitiveComparisonFastPath = true
                if args.count == 3 {
                    var tentativeLocals = locals
                    let secondArgType = driver.inferExpr(
                        args[1].expr,
                        ctx: ctx,
                        locals: &tentativeLocals,
                        expectedType: resolvedParamType
                    )
                    let thirdArgType = driver.inferExpr(
                        args[2].expr,
                        ctx: ctx,
                        locals: &tentativeLocals,
                        expectedType: resolvedParamType
                    )
                    shouldUsePrimitiveComparisonFastPath = secondArgType == resolvedParamType && thirdArgType == resolvedParamType
                }

                if shouldUsePrimitiveComparisonFastPath,
                   let specialKind = comparisonSpecialCallKind(
                    for: calleeName,
                    argCount: args.count,
                    resolvedParamType: resolvedParamType,
                    ctx: ctx,
                    locals: locals
                ) {
                    let expectedType = resolvedParamType

                    // An unsuffixed literal first argument may adopt a wider
                    // parameter type selected by a sibling argument (e.g. `1`
                    // in `maxOf(1, 2L)` binds as Long); re-infer it against the
                    // resolved type so the constraint and KIR see Long.
                    let firstArgumentType = firstArgType == expectedType
                        ? firstArgType
                        : driver.inferExpr(
                            args[0].expr,
                            ctx: ctx,
                            locals: &locals,
                            expectedType: expectedType
                        )
                    driver.emitSubtypeConstraint(
                        left: firstArgumentType,
                        right: expectedType,
                        range: ast.arena.exprRange(args[0].expr) ?? range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.sema.diagnostics,
                        diagnosticCode: "KSWIFTK-SEMA-0473",
                        failureMessage: "Argument type mismatch."
                    )

                    for i in 1 ..< args.count {
                        let argType = driver.inferExpr(
                            args[i].expr,
                            ctx: ctx,
                            locals: &locals,
                            expectedType: expectedType
                        )
                        driver.emitSubtypeConstraint(
                            left: argType,
                            right: expectedType,
                            range: ast.arena.exprRange(args[i].expr) ?? range,
                            solver: ConstraintSolver(),
                            sema: sema,
                            diagnostics: ctx.sema.diagnostics,
                            diagnosticCode: "KSWIFTK-SEMA-0473",
                            failureMessage: "Argument type mismatch."
                        )
                    }

                    let paramTypes = Array(repeating: expectedType, count: args.count)
                    let matchingCandidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible.filter { candidate in
                        guard let signature = sema.symbols.functionSignature(for: candidate) else {
                            return false
                        }
                        return signature.parameterTypes == paramTypes
                    }
                    // Prefer the fixed-arity overload over a vararg one declaring the same
                    // parameter types (e.g. minOf(Int, Int) vs minOf(Int, vararg Int)), matching
                    // Kotlin's preference for non-vararg signatures during overload resolution.
                    let chosen = matchingCandidates.first(where: { candidate in
                        guard let signature = sema.symbols.functionSignature(for: candidate) else {
                            return false
                        }
                        return !signature.valueParameterIsVararg.contains(true)
                    }) ?? matchingCandidates.first
                    if let chosen,
                       let signature = sema.symbols.functionSignature(for: chosen)
                    {
                        var paramMapping: [Int: Int] = [:]
                        for i in 0 ..< args.count {
                            paramMapping[i] = i
                        }
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [],
                                parameterMapping: paramMapping
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                        sema.bindings.markStdlibSpecialCallExpr(id, kind: specialKind)
                        sema.bindings.bindExprType(id, type: signature.returnType)
                        return signature.returnType
                    }
                    sema.bindings.markStdlibSpecialCallExpr(id, kind: specialKind)
                    sema.bindings.bindExprType(id, type: expectedType)
                    return expectedType
                }
            }
        }
        return nil
    }

    /// Resolves the primitive parameter type for the minOf/maxOf fast path.
    ///
    /// An unsuffixed integer literal keeps Kotlin's integer-literal type
    /// through overload resolution, so when the first argument is such a
    /// literal a concrete sibling argument selects the wider primitive
    /// overload instead of the literal's default Int (`maxOf(1, 2L)` resolves
    /// to `maxOf(Long, Long)`); when every argument is a literal, a value
    /// outside Int range selects Long the same way (`maxOf(1, 5000000000)`).
    /// Returns nil when the arguments cannot share one supported primitive
    /// type, leaving the call to general overload resolution.
    private func primitiveMinMaxParameterType(
        args: [CallArgument],
        firstArgType: TypeID,
        supportedNumericTypes: [TypeID],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let ast = ctx.ast
        guard integerLiteralValues(args[0].expr, ast: ast).signed != nil else {
            return supportedNumericTypes.first(where: { $0 == firstArgType })
        }

        var concreteType: TypeID?
        for index in 1 ..< args.count {
            guard integerLiteralValues(args[index].expr, ast: ast).signed == nil else {
                continue
            }
            let type = driver.inferExpr(
                args[index].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: nil
            )
            if let concreteType, concreteType != type {
                return nil
            }
            concreteType = type
        }

        let parameterType: TypeID
        if let concreteType {
            parameterType = concreteType
        } else if args.contains(where: { argument in
            guard let value = integerLiteralValues(argument.expr, ast: ast).signed else {
                return false
            }
            return value < Int64(Int32.min) || value > Int64(Int32.max)
        }) {
            // Every argument is an unsuffixed literal and one cannot be an
            // Int, so the call resolves to the Long overload like Kotlin's
            // integer-literal typing (`maxOf(1, 5000000000)`).
            parameterType = ctx.sema.types.longType
        } else {
            parameterType = firstArgType
        }
        guard supportedNumericTypes.contains(parameterType),
              signedIntegerLiteralArgumentsFit(args: args, parameterType: parameterType, ctx: ctx)
        else {
            return nil
        }
        return parameterType
    }

    /// Whether every unsuffixed integer literal argument's value fits the
    /// primitive parameter type, mirroring the literal adoption Kotlin
    /// applies during overload resolution.
    private func signedIntegerLiteralArgumentsFit(
        args: [CallArgument],
        parameterType: TypeID,
        ctx: TypeInferenceContext
    ) -> Bool {
        let sema = ctx.sema
        guard case let .primitive(primitive, _) = sema.types.kind(of: sema.types.makeNonNullable(parameterType)) else {
            return false
        }
        for argument in args {
            guard let value = integerLiteralValues(argument.expr, ast: ctx.ast).signed else {
                continue
            }
            let fits: Bool
            switch primitive {
            case .byte:
                fits = (-128 ... 127).contains(value)
            case .short:
                fits = (-32768 ... 32767).contains(value)
            case .int:
                fits = value >= Int64(Int32.min) && value <= Int64(Int32.max)
            case .long:
                fits = true
            default:
                fits = false
            }
            guard fits else {
                return false
            }
        }
        return true
    }

    /// Selector lambdas for the comparison helpers return `Comparable<*>?` per
    /// their Kotlin signatures. Typing them as `Any?` boxes results into `Any`,
    /// which then fails the `as Comparable<Any>` check inside `compareValues`.
    private func comparisonSelectorReturnType(sema: SemaModule, interner: StringInterner) -> TypeID {
        let comparableFQName = [interner.intern("kotlin"), interner.intern("Comparable")]
        guard let comparableSymbol = sema.symbols.lookup(fqName: comparableFQName) else {
            return sema.types.nullableAnyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.star],
            nullability: .nullable
        )))
    }

    func resolveCompareBySelectorArguments(
        calleeName: InternedString?,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> [Bool] {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        let compareBySelectorArguments: [Bool]
        if let calleeName,
           calleeName == knownNames.compareBy || calleeName == knownNames.compareByDescending,
           args.count == 2 || args.count == 3,
           locals[calleeName] == nil
        {
            compareBySelectorArguments = args.map { argument -> Bool in
                if isLambdaOrCallableRefArg(argument.expr, ast: ast) {
                    return true
                }
                let argumentType = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
                guard case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(argumentType)) else {
                    return false
                }
                return functionType.params.count == 1
            }
        } else {
            compareBySelectorArguments = []
        }
        return compareBySelectorArguments
    }

    func inferCompareBySelectorsCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        compareBySelectorArguments: [Bool]
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)


        if let calleeName,
           args.count == 2 || args.count == 3,
           calleeName == knownNames.compareBy,
           compareBySelectorArguments.allSatisfy({ $0 }),
           locals[calleeName] == nil,
           sourceOrSyntheticStdlibFunctionSymbol(
               calleeName,
               fqComponents: ["kotlin", "comparisons", "compareBy"],
               ctx: ctx
           ) != nil
        {
            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
            let elementType: TypeID = if let explicitT = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs) {
                explicitT
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: expectedType),
                      let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                params: [elementType],
                returnType: comparisonSelectorReturnType(sema: sema, interner: interner),
                isSuspend: false,
                nullability: .nonNull
            )))
            for arg in args {
                sema.bindings.markCollectionHOFLambdaExpr(arg.expr)
                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)
            }
            let resultType: TypeID = if let comparatorSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
            let funcFQName = comparisonsPkg + [calleeName]
            if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                guard let sig = sema.symbols.functionSignature(for: candidate),
                      sema.symbols.isSourceBackedSymbol(candidate)
                else { return false }
                return sig.parameterTypes.count == args.count &&
                    !sig.valueParameterIsVararg.contains(true) &&
                    sig.parameterTypes.allSatisfy { paramType in
                        if case .functionType = sema.types.kind(of: paramType) { return true }
                        return false
                    }
            }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [elementType],
                        parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }
        return nil
    }

    func inferCompareByPairCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        compareBySelectorArguments: [Bool]
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        if let calleeName,
           args.count == 2,
           calleeName == knownNames.compareBy || calleeName == knownNames.compareByDescending,
           compareBySelectorArguments.first == false,
           locals[calleeName] == nil,
           sourceOrSyntheticStdlibFunctionSymbol(
               calleeName,
               fqComponents: ["kotlin", "comparisons", interner.resolve(calleeName)],
               ctx: ctx
           ) != nil
        {
            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
            let elementType: TypeID = if let explicitT = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs) {
                explicitT
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: expectedType),
                      let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let keyType: TypeID = if let explicit = resolvedExplicitTypeArgument(at: 1, in: explicitTypeArgs) {
                explicit
            } else {
                sema.types.anyType
            }
            let keyComparatorType: TypeID = if let comparatorSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(keyType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: keyComparatorType)

            let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                params: [elementType],
                returnType: keyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let lambdaExpr = ast.arena.expr(args[1].expr), case .lambdaLiteral = lambdaExpr {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)

            let resultType: TypeID = if let comparatorSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
            let funcFQName = comparisonsPkg + [calleeName]
            if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                guard let sig = sema.symbols.functionSignature(for: candidate),
                      sema.symbols.isSourceBackedSymbol(candidate)
                else { return false }
                return sig.parameterTypes.count == 2
                    && !sig.valueParameterIsVararg.contains(true)
            }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [elementType, keyType],
                        parameterMapping: [0: 0, 1: 1]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }
        return nil
    }

    func inferCompareByVarargCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)


        if let calleeName,
           args.count >= 4,
           calleeName == knownNames.compareBy,
           locals[calleeName] == nil,
           sourceOrSyntheticStdlibFunctionSymbol(
               calleeName,
               fqComponents: ["kotlin", "comparisons", "compareBy"],
               ctx: ctx
           ) != nil
        {
            let elementType: TypeID = if let explicitT = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs) {
                explicitT
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: expectedType),
                      let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                params: [elementType],
                returnType: comparisonSelectorReturnType(sema: sema, interner: interner),
                isSuspend: false,
                nullability: .nonNull
            )))
            for arg in args {
                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)
            }

            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
            let resultType: TypeID = if let comparatorSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }

            let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
            let funcFQName = comparisonsPkg + [calleeName]
            if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                guard let sig = sema.symbols.functionSignature(for: candidate),
                      sema.symbols.isSourceBackedSymbol(candidate)
                else { return false }
                return sig.valueParameterIsVararg == [true]
            }) {
                var mapping: [Int: Int] = [:]
                for index in args.indices {
                    mapping[index] = 0
                }
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [elementType],
                        parameterMapping: mapping
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }
        return nil
    }

    func inferCompareBySingleSelectorCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner


        if let calleeName,
           args.count == 1,
           locals[calleeName] == nil
        {
            let calleeNameStr = interner.resolve(calleeName)
            if (calleeNameStr == "compareBy" || calleeNameStr == "compareByDescending"),
               sourceOrSyntheticStdlibFunctionSymbol(
                   calleeName,
                   fqComponents: ["kotlin", "comparisons", calleeNameStr],
                   ctx: ctx
               ) != nil {
                let elementType: TypeID = if let explicitT = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs) {
                    explicitT
                } else if let expectedType,
                    case let .classType(classType) = sema.types.kind(of: expectedType),
                    let firstArg = classType.args.first
                {
                    switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [elementType],
                    returnType: comparisonSelectorReturnType(sema: sema, interner: interner),
                    isSuspend: false,
                    nullability: .nonNull
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)

                let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
                let resultType: TypeID = if let comparatorSymbol {
                    sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(elementType)],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }

                let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
                let funcFQName = comparisonsPkg + [calleeName]
                if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                    guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                    return sig.parameterTypes.count == 1
                        && sig.valueParameterIsVararg != [true]
                }) {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [elementType],
                            parameterMapping: [0: 0]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }
        return nil
    }

    func inferNaturalOrderCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner


        if let calleeName,
           args.isEmpty,
           locals[calleeName] == nil
        {
            let calleeNameStr = interner.resolve(calleeName)
            if (calleeNameStr == "naturalOrder" || calleeNameStr == "reverseOrder"),
               sourceOrSyntheticStdlibFunctionSymbol(
                   calleeName,
                   fqComponents: ["kotlin", "comparisons", calleeNameStr],
                   ctx: ctx
               ) != nil {
                let elementType: TypeID = if let explicitTypeArg = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs) {
                    explicitTypeArg
                } else if let expectedType,
                    case let .classType(classType) = sema.types.kind(of: expectedType),
                    let firstArg = classType.args.first
                {
                    switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }

                let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
                let resultType: TypeID = if let comparatorSymbol {
                    sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(elementType)],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }

                let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
                let funcFQName = comparisonsPkg + [calleeName]
                if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                    guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                    return sig.parameterTypes.isEmpty
                }) {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [elementType],
                            parameterMapping: [:]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }
        return nil
    }

    func inferCompareValuesByCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        candidates: [SymbolID]
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        if let calleeName,
           calleeName == knownNames.compareValuesBy,
           args.count >= 3,
           locals[calleeName] == nil,
           sourceOrSyntheticStdlibFunctionSymbol(
               calleeName,
               fqComponents: ["kotlin", "comparisons", "compareValuesBy"],
               ctx: ctx
           ) != nil
        {
            let firstType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let secondType = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals)
            let comparatorArgType: TypeID? = if args.count == 4,
                                               !isLambdaOrCallableRefArg(args[2].expr, ast: ast)
            {
                driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals)
            } else {
                nil
            }
            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            if let comparatorArgType,
               let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
            {
                let nonNullComparatorArgType = sema.types.makeNonNullable(comparatorArgType)
                let inferredKeyType: TypeID? = if case let .classType(classType) = sema.types.kind(of: nonNullComparatorArgType),
                                                  classType.classSymbol == comparatorSymbol,
                                                  let firstArg = classType.args.first
                {
                    switch firstArg {
                    case let .invariant(type), let .out(type), let .in(type): type
                    case .star: sema.types.anyType
                    }
                } else {
                    nil
                }

                if let inferredKeyType {
                    let elementCandidates = [firstType, secondType].filter { $0 != sema.types.errorType }.map {
                        sema.types.makeNonNullable($0)
                    }
                    let elementType = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs)
                        ?? (elementCandidates.isEmpty ? sema.types.anyType : sema.types.lub(elementCandidates))
                    let keyType = resolvedExplicitTypeArgument(at: 1, in: explicitTypeArgs) ?? inferredKeyType
                    let comparatorType = sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(keyType)],
                        nullability: .nonNull
                    )))
                    let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [elementType],
                        returnType: keyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: comparatorType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[3].expr)
                    _ = driver.inferExpr(args[3].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)

                    if let chosen = candidates.first(where: { candidate in
                        guard let sig = sema.symbols.functionSignature(for: candidate),
                              sema.symbols.isSourceBackedSymbol(candidate)
                        else { return false }
                        return sig.parameterTypes.count == 4 && sig.typeParameterSymbols.count == 2
                    }) {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [elementType, keyType],
                                parameterMapping: [0: 0, 1: 1, 2: 2, 3: 3]
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                    }
                    sema.bindings.bindExprType(id, type: sema.types.intType)
                    return sema.types.intType
                }
            }
            // The one-selector overload has three source arguments (including
            // a trailing lambda). Infer T from both compared values before
            // contextualizing its selector, just as the multi-selector path does.
            if args.count >= 3 {
                let elementCandidates = [firstType, secondType].filter { $0 != sema.types.errorType }.map {
                    sema.types.makeNonNullable($0)
                }
                let elementType = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs)
                    ?? (elementCandidates.isEmpty ? sema.types.anyType : sema.types.lub(elementCandidates))
                let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [elementType],
                    returnType: comparisonSelectorReturnType(sema: sema, interner: interner),
                    isSuspend: false,
                    nullability: .nonNull
                )))
                for index in 2..<args.count {
                    if case .lambdaLiteral = ast.arena.expr(args[index].expr) {
                        sema.bindings.bindFunctionValueExpectedType(args[index].expr, type: selectorExpectedType)
                    }
                    _ = driver.inferExpr(args[index].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)
                }

                // 3 selectors resolve to the fixed-arity overload; 4+ to the vararg one.
                let usesVararg = args.count > 5
                if let chosen = candidates.first(where: { candidate in
                    guard let sig = sema.symbols.functionSignature(for: candidate),
                          sema.symbols.isSourceBackedSymbol(candidate)
                    else { return false }
                    // The comparator overload has the same arity as the two
                    // selector one, so match on its second type parameter (`K`).
                    return usesVararg
                        ? sig.valueParameterIsVararg == [false, false, true]
                        : (sig.parameterTypes.count == args.count
                            && sig.typeParameterSymbols.count == 1
                            && !sig.valueParameterIsVararg.contains(true))
                }) {
                    var mapping: [Int: Int] = [0: 0, 1: 1]
                    for index in 2..<args.count {
                        mapping[index] = usesVararg ? 2 : index
                    }
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [elementType],
                            parameterMapping: mapping
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                sema.bindings.bindExprType(id, type: sema.types.intType)
                return sema.types.intType
            }
        }
        return nil
    }
}
