// swiftlint:disable file_length function_body_length cyclomatic_complexity

/// Array-constructor call interceptions from the `inferCallExpr` dispatch
/// chain: `Array(size) { init }` (source-backed and intrinsic forms) and the
/// `AtomicIntArray` / `AtomicLongArray` element-type fast paths.
/// Extracted from `CallTypeChecker+CallExprInference.swift`.
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


        // --- Stdlib Array(size) { init } constructor (STDLIB-085/086, TYPE-103) ---
        // A visible source-backed top-level function with the same name and applicable
        // arity owns the overload. For one-argument primitive arrays, compare
        // the inferred argument type as well: UByteArray(ByteArray) must not
        // hide the compiler-provided UByteArray(Int) allocation form.
        let sourceBackedArrayConstructors: [(symbol: SymbolID, signature: FunctionSignature)] = if let calleeName {
            ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible.compactMap { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
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
               knownNames.isPrimitiveArrayConstructorTypeName(calleeName),
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
           knownNames.isPrimitiveArrayConstructorTypeName(calleeName),
           args.count == 1 || args.count == 2,
           locals[calleeName] == nil,
           !hasSourceBackedArrayConstructor
        {
            let intType = sema.types.intType
            let calleeNameStr = interner.resolve(calleeName)
            // Intrinsic allocation bypasses normal constructor resolution, but
            // still uses the source-backed array class's opt-in contract.
            if let arraySymbol = sema.symbols.lookup(
                fqName: [interner.intern("kotlin"), calleeName]
            ) {
                driver.helpers.checkOptIn(
                    for: arraySymbol,
                    ctx: ctx,
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
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
                diagnostics: ctx.semaCtx.diagnostics
            )
            if args.count == 1 {
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .arrayConstructor)
                sema.bindings.markCollectionExpr(id)
                let resultType: TypeID = if calleeNameStr == "Array" {
                    makeSyntheticArrayType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: {
                            if let explicitTypeArg = explicitTypeArgs.first {
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
            // Determine the element type from the expected type annotation or
            // the init lambda's return type, avoiding erasure to Any.
            //
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
               let explicitTypeArg = explicitTypeArgs.first
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
                // No expected type and no explicit type argument for Array(size) { init }.
                // Infer the lambda with `it` constrained to Int, then extract the
                // actual body return type from bindings to avoid erasing to Any.
                let lambdaExpected = sema.types.make(.functionType(FunctionType(
                    params: [intType],
                    returnType: sema.types.makeNullable(sema.types.anyType)
                )))
                _ = driver.inferExpr(
                    args[1].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: lambdaExpected
                )
                // Read back the lambda body's actual inferred type.
                let bodyType: TypeID? = if case let .lambdaLiteral(_, body, _, _) = ast.arena.expr(args[1].expr) {
                    sema.bindings.exprTypes[body]
                } else {
                    nil
                }
                let inferred = bodyType ?? sema.types.anyType
                elementReturnType = (inferred != sema.types.errorType) ? inferred : sema.types.anyType
            } else {
                // For primitive array constructors, the element type is fixed.
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
                args[1].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: initExpectedType
            )
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .arrayConstructor)
            sema.bindings.markCollectionExpr(id)
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
                diagnostics: ctx.semaCtx.diagnostics
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
                diagnostics: ctx.semaCtx.diagnostics
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
