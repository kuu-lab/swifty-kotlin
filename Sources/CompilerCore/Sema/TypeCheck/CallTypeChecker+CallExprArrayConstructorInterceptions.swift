// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func inferArrayConstructorCall(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)


        let arrayConstructorTarget = arrayConstructorTarget(
            calleeName: calleeName,
            explicitTypeArgs: explicitTypeArgs,
            expectedType: expectedType,
            locals: locals,
            ctx: ctx,
            knownNames: knownNames
        )
        // A visible source-backed top-level function with the same name and applicable
        // arity owns the overload. For one-argument primitive arrays, compare
        // the inferred argument type as well: UByteArray(ByteArray) must not
        // hide the compiler-provided UByteArray(Int) allocation form.
        let sourceBackedArrayConstructors: [(symbol: SymbolID, signature: FunctionSignature)] = if let calleeName {
            ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible.compactMap { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      // The external allocation declarations exist to make
                      // callable references visible. Direct size-only calls
                      // must keep using the compiler intrinsic below.
                      sema.symbols.externalLinkName(for: candidate) != "kk_array_new_checked",
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.receiverType == nil,
                      signature.parameterTypes.count == args.count,
                      !signature.valueParameterIsVararg.contains(true)
                else {
                    return nil
                }
                return (candidate, signature)
            }
        } else {
            []
        }
        let hasSourceBackedArrayConstructor: Bool = {
            if args.count == 1,
               let calleeName,
               knownNames.isArrayLikeName(calleeName),
               !sourceBackedArrayConstructors.isEmpty
            {
                let argumentType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                return sourceBackedArrayConstructors.contains { _, signature in
                    guard let parameterType = signature.parameterTypes.first else {
                        return false
                    }
                    return sema.types.isSubtype(argumentType, parameterType)
                }
            }
            return !sourceBackedArrayConstructors.isEmpty
        }()
        if let calleeName,
           let arrayConstructorTarget,
           args.count == 1 || args.count == 2,
           locals[calleeName] == nil,
           !hasSourceBackedArrayConstructor
        {
            var indices: [Int: Int] = [:]
            for (i, argument) in args.enumerated() {
                let parameter = argument.label.map { interner.resolve($0) == "size" ? 0 : (interner.resolve($0) == "init" ? 1 : -1) } ?? i
                guard (0...1).contains(parameter), indices[parameter] == nil, !argument.isSpread else {
                    sema.diagnostics.error("KSWIFTK-SEMA-0001", "Invalid array constructor argument.", range: range)
                    return sema.types.errorType
                }
                indices[parameter] = i
            }
            guard let sizeIndex = indices[0], args.count == 1 || indices[1] != nil else {
                sema.diagnostics.error("KSWIFTK-SEMA-0001", "Array constructor requires size and an optional init argument.", range: range)
                return sema.types.errorType
            }
            let initializerIndex = indices[1] ?? 1
            let intType = sema.types.intType
            let arrayName = arrayConstructorTarget.name
            let calleeNameStr = interner.resolve(arrayName)
            // Intrinsic allocation bypasses normal constructor resolution, but
            // still uses the source-backed array class's opt-in contract.
            if let arraySymbol = sema.symbols.lookup(
                fqName: [interner.intern("kotlin"), arrayName]
            ) {
                driver.helpers.checkOptIn(
                    for: arraySymbol,
                    ctx: ctx,
                    range: range,
                    diagnostics: ctx.sema.diagnostics
                )
            }
            let countType = driver.inferExpr(
                args[sizeIndex].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            driver.emitSubtypeConstraint(
                left: countType,
                right: intType,
                range: ast.arena.exprRange(args[sizeIndex].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.sema.diagnostics
            )
            if args.count == 1 {
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .arrayConstructor)
                // Primitive arrays use their nominal source APIs instead of the synthetic
                // collection/Sequence HOF path.
                if calleeNameStr == "Array" {
                    sema.bindings.markCollectionExpr(id)
                }
                let resultType: TypeID = if calleeNameStr == "Array" {
                    makeSyntheticArrayType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: {
                            if let explicitTypeArg = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs) {
                                explicitTypeArg
                            } else if let kotlinArraySymbol = sema.symbols.lookup(
                                fqName: [interner.intern("kotlin"), interner.intern("Array")]
                            ), let expectedType,
                                      case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                                      expectedClassType.classSymbol == kotlinArraySymbol,
                                      let firstArg = expectedClassType.args.first
                            {
                                switch firstArg {
                                case let .invariant(type), let .in(type), let .out(type):
                                    type
                                case .star:
                                    sema.types.anyType
                                }
                            } else {
                                sema.types.anyType
                            }
                        }()
                    )
                } else {
                    makeSyntheticPrimitiveArrayType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        arrayName: calleeNameStr
                    )
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
            // Only extract the generic argument from the expected type when:
            //   1. The callee is "Array" (not a primitive array like IntArray), AND
            //   2. The expected type is actually kotlin.Array<...> (not some unrelated
            //      generic type like List<String>).
            // Primitive arrays (IntArray, LongArray, etc.) have fixed element types
            // that must not be overridden by contextual expected types.
            let arrayFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("Array"),
            ]
            let kotlinArraySymbol = sema.symbols.lookup(fqName: arrayFQName)
            let isKotlinArray = calleeNameStr == "Array"
            let elementReturnType: TypeID
            if isKotlinArray,
               let aliasElementType = arrayConstructorTarget.elementType
            {
                elementReturnType = aliasElementType
            } else if isKotlinArray,
               let explicitTypeArg = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs)
            {
                elementReturnType = explicitTypeArg
            } else if isKotlinArray,
               let kotlinArraySymbol,
               let expectedType, expectedType != sema.types.errorType,
               case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
               expectedClassType.classSymbol == kotlinArraySymbol,
               let firstArg = expectedClassType.args.first
            {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    elementReturnType = type
                case .star:
                    elementReturnType = sema.types.anyType
                }
            } else if isKotlinArray {
                // Infer the lambda with `it` constrained to Int, then extract the
                // actual body return type from bindings to avoid erasing to Any.
                let lambdaExpected = sema.types.make(.functionType(FunctionType(
                    params: [intType],
                    returnType: sema.types.makeNullable(sema.types.anyType)
                )))
                _ = driver.inferExpr(
                    args[initializerIndex].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: lambdaExpected
                )
                let bodyType: TypeID? = if case let .lambdaLiteral(_, body, _, _) = ast.arena.expr(args[initializerIndex].expr) {
                    sema.bindings.exprTypes[body]
                } else {
                    nil
                }
                let inferred = bodyType ?? sema.types.anyType
                elementReturnType = (inferred != sema.types.errorType) ? inferred : sema.types.anyType
            } else {
                elementReturnType = switch calleeNameStr {
                case "IntArray": sema.types.intType
                case "LongArray": sema.types.longType
                case "ShortArray": sema.types.shortType
                case "ByteArray": sema.types.byteType
                case "UByteArray": sema.types.ubyteType
                case "UShortArray": sema.types.ushortType
                case "UIntArray": sema.types.uintType
                case "DoubleArray": sema.types.make(.primitive(.double, .nonNull))
                case "FloatArray": sema.types.make(.primitive(.float, .nonNull))
                case "BooleanArray": sema.types.booleanType
                case "CharArray": sema.types.make(.primitive(.char, .nonNull))
                default: sema.types.anyType
                }
            }
            let initExpectedType = sema.types.make(.functionType(FunctionType(
                params: [intType],
                returnType: elementReturnType
            )))
            // Always infer the init lambda against `(Int) -> elementReturnType`.
            // Skipping it leaves the lambda's index parameter unbound, so
            // `Array<Int>(3) { it }` lowers with a zero index for every slot.
            _ = driver.inferExpr(
                args[initializerIndex].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: initExpectedType
            )
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .arrayConstructor)
            if calleeNameStr == "Array" {
                sema.bindings.markCollectionExpr(id)
            }
            let resultType: TypeID
            if calleeNameStr == "Array" {
                resultType = makeSyntheticArrayType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: elementReturnType
                )
            } else {
                resultType = makeSyntheticPrimitiveArrayType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    arrayName: calleeNameStr
                )
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }
        return nil
    }

    private func arrayConstructorTarget(
        calleeName: InternedString?,
        explicitTypeArgs: [TypeID],
        expectedType: TypeID?,
        locals: LocalBindings,
        ctx: TypeInferenceContext,
        knownNames: KnownCompilerNames
    ) -> (name: InternedString, elementType: TypeID?)? {
        guard let calleeName, locals[calleeName] == nil else { return nil }
        if knownNames.isArrayLikeName(calleeName) {
            // A declaration that does not come from the kotlin.* default
            // imports — a file-local or same-package classifier, typealias,
            // or callable — shadows the bundled kotlin.<Name> array type.
            // Leave the call to ordinary call resolution so `UIntArray(5)`
            // reaches the user declaration instead of the array intrinsic
            // (KUU-3615). fqName-less synthetic stubs are compiler-owned and
            // cannot shadow.
            let isShadowedByNonKotlinSymbol = ctx.cachedScopeLookup(calleeName).contains { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      !symbol.fqName.isEmpty
                else {
                    return false
                }
                return symbol.fqName.first != ctx.interner.intern("kotlin")
            }
            if isShadowedByNonKotlinSymbol {
                return nil
            }
            return (calleeName, nil)
        }

        let sema = ctx.sema
        let interner = ctx.interner
        let visibleSymbols = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        guard !visibleSymbols.contains(where: { candidate in
            guard let symbol = ctx.cachedSymbol(candidate) else { return false }
            return symbol.kind == .function || symbol.kind == .constructor
        }) else {
            return nil
        }

        let aliases = visibleSymbols.filter { ctx.cachedSymbol($0)?.kind == .typeAlias }
        for alias in aliases {
            let typeParameters = sema.symbols.typeAliasTypeParameters(for: alias)
            let aliasTypeArgs: [TypeArg] = if !explicitTypeArgs.isEmpty {
                explicitTypeArgs.enumerated().map { index, type in
                    if type == TypeID.invalid, typeParameters.indices.contains(index) {
                        return .invariant(sema.types.make(.typeParam(TypeParamType(symbol: typeParameters[index]))))
                    }
                    return .invariant(type)
                }
            } else if !typeParameters.isEmpty,
                      let expectedType,
                      case let .classType(expectedClassType) = sema.types.kind(of: expectedType)
            {
                Array(expectedClassType.args.prefix(typeParameters.count))
            } else {
                typeParameters.map { parameter in
                    .invariant(sema.types.make(.typeParam(TypeParamType(symbol: parameter))))
                }
            }
            guard let expanded = driver.helpers.expandTypeAlias(
                alias,
                typeArgs: aliasTypeArgs,
                sema: sema,
                visited: [],
                depth: 0,
                diagnostics: ctx.sema.diagnostics
            ),
                  case let .classType(classType) = sema.types.kind(of: expanded),
                  classType.nullability == .nonNull,
                  let targetSymbol = sema.symbols.symbol(classType.classSymbol),
                  targetSymbol.fqName.count == 2,
                  targetSymbol.fqName[0] == interner.intern("kotlin"),
                  knownNames.isArrayLikeName(targetSymbol.name)
            else {
                continue
            }

            let elementType: TypeID?
            if targetSymbol.name == knownNames.array, let firstArg = classType.args.first {
                let type: TypeID = switch firstArg {
                case let .invariant(type), let .in(type), let .out(type): type
                case .star: sema.types.anyType
                }
                if case let .typeParam(typeParameter) = sema.types.kind(of: type),
                   typeParameters.contains(typeParameter.symbol)
                {
                    elementType = nil
                } else {
                    elementType = type
                }
            } else {
                elementType = nil
            }
            return (targetSymbol.name, elementType)
        }
        return nil
    }

    func inferAtomicIntArrayCall(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        if let calleeName,
           (args.count == 1 || args.count == 2),
           calleeName == knownNames.atomicIntArray,
           !hasSourceBackedAtomicArrayFactory(
               calleeName,
               className: "AtomicIntArray",
               argumentCount: args.count,
               ctx: ctx
           ),
           !isShadowedByNonSyntheticSymbol(
               calleeName,
               locals: locals,
               ctx: ctx,
               argumentCount: args.count
           ),
           let arraySymbol = syntheticAtomicArrayClassSymbol(
               calleeName,
               className: "AtomicIntArray",
               ctx: ctx
           )
        {
            let intType = sema.types.intType
            let countType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            driver.emitSubtypeConstraint(
                left: countType,
                right: intType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.sema.diagnostics
            )
            if args.count == 2 {
                let initExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [intType],
                    returnType: intType
                )))
                _ = driver.inferExpr(
                    args[1].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: initExpectedType
                )
            }
            let resultType = sema.types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [],
                nullability: .nonNull
            )))
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .atomicIntArrayFactory)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }
        return nil
    }

    func inferAtomicLongArrayCall(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        if let calleeName,
           (args.count == 1 || args.count == 2),
           calleeName == knownNames.atomicLongArray,
           !hasSourceBackedAtomicArrayFactory(
               calleeName,
               className: "AtomicLongArray",
               argumentCount: args.count,
               ctx: ctx
           ),
           !isShadowedByNonSyntheticSymbol(
               calleeName,
               locals: locals,
               ctx: ctx,
               argumentCount: args.count
           ),
           let arraySymbol = syntheticAtomicArrayClassSymbol(
               calleeName,
               className: "AtomicLongArray",
               ctx: ctx
           )
        {
            let intType = sema.types.intType
            let longType = sema.types.longType
            let countType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            driver.emitSubtypeConstraint(
                left: countType,
                right: intType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.sema.diagnostics
            )
            if args.count == 2 {
                let initExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [intType],
                    returnType: longType
                )))
                _ = driver.inferExpr(
                    args[1].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: initExpectedType
                )
            }
            let resultType = sema.types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [],
                nullability: .nonNull
            )))
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .atomicLongArrayFactory)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }
        return nil
    }
}
