// A lambda argument returns into an *erased* position when the higher-order
// function it is passed to declares that return as a type parameter (`R`).
// Values flowing through an erased position are boxed at runtime (the generic
// body is compiled once and stores `Any`-sized words), while the lambda body is
// type-checked against the *substituted* concrete type (`Char`, `Boolean`, ...).
// Without a bridge the two representations disagree: a `Char`-returning lambda
// passed to `fun <R> CharSequence.map(transform: (Char) -> R): List<R>` hands
// the raw scalar to the generic body, which stores it unboxed into `List<R>`,
// so printing the list yields `97` instead of `a`.

extension LambdaLowerer {
    /// Widens a lowered lambda's declared return type to `Any` when it returns
    /// into an erased position, matching the value `boxErasedReturnValue` emits.
    func erasedLambdaReturnType(
        _ returnType: TypeID,
        returnsErasedGeneric: Bool,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        erasedReturnBoxCallee(returnType, returnsErasedGeneric: returnsErasedGeneric, sema: sema, interner: interner) != nil
            ? sema.types.anyType
            : returnType
    }

    /// Boxes a concrete value flowing out of an erased return position.
    ///
    /// The box is emitted here rather than left to `ABILoweringPass` because the
    /// lambda's own declared return type stays concrete in the substituted
    /// signature, so the ABI pass does not recognise the boundary.
    func boxErasedReturnValue(
        _ value: KIRExprID,
        returnType: TypeID,
        returnsErasedGeneric: Bool,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let returnedValue: KIRExprID
        if returnType == sema.types.unitType {
            // The body still runs for its side effects, but a Unit callback
            // returns Unit even when its last expression produced a value.
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            returnedValue = unit
        } else {
            returnedValue = value
        }
        guard returnsErasedGeneric else {
            return returnedValue
        }
        // Prefer the lowered expression's concrete type over the contextual
        // function return type. Generic inference may record that return type
        // as `Any`, while a value-class expression such as `{ it }` still needs
        // its nominal class tag when it crosses the erased boundary.
        let sourceType = arena.exprType(returnedValue) ?? returnType
        return boxValueForAnySlot(
            returnedValue,
            sourceType: sourceType,
            types: sema.types,
            symbols: sema.symbols,
            interner: interner,
            arena: arena,
            resultType: sema.types.anyType,
            requireNonNull: true,
            sema: sema,
            into: &instructions
        )
    }

    private func erasedReturnBoxCallee(
        _ returnType: TypeID,
        returnsErasedGeneric: Bool,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        guard returnsErasedGeneric,
              let callee = BoxingCalleeTable(interner: interner).boxCallee(
                  for: resolveValueClassKind(
                      sema.types.kind(of: returnType),
                      types: sema.types,
                      symbols: sema.symbols
                  ),
                  requireNonNull: true
              )
        else {
            return nil
        }
        return callee
    }
}

extension KIRLoweringContext {
    func lambdaReturnsErasedGeneric(
        for exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> Bool {
        erasedLambdaReturnClaim(for: exprID, ast: ast, sema: sema) != nil
    }

    /// The declared return type parameter and the call-site substitution for
    /// a lambda passed to a `() -> T`-returning parameter, when the lambda
    /// argument is itself a literal. Erased-call claim checks inside the
    /// body must verify the *substituted* claim: JVM specializes the
    /// lambda's invoke() to the call-site type argument and emits the
    /// boundary checkcast there (KUU-4496).
    func erasedLambdaReturnClaim(
        for exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> (declaredSymbol: SymbolID, substituted: TypeID)? {
        if erasedGenericReturnLambdaClaims == nil {
            erasedGenericReturnLambdaClaims = Self.collectErasedGenericReturnLambdaClaims(ast: ast, sema: sema)
        }
        return erasedGenericReturnLambdaClaims?[exprID]
    }

    private static func collectErasedGenericReturnLambdaClaims(
        ast: ASTModule,
        sema: SemaModule
    ) -> [ExprID: (declaredSymbol: SymbolID, substituted: TypeID)] {
        var result: [ExprID: (SymbolID, TypeID)] = [:]
        for (callExprID, binding) in sema.bindings.callBindings {
            guard let signature = sema.symbols.functionSignature(for: binding.chosenCallee),
                  let arguments = callArguments(of: callExprID, ast: ast)
            else {
                continue
            }
            for (argIndex, paramIndex) in binding.parameterMapping {
                guard argIndex >= 0, argIndex < arguments.count,
                      paramIndex >= 0, paramIndex < signature.parameterTypes.count
                else {
                    continue
                }
                let argExprID = arguments[argIndex].expr
                guard case .lambdaLiteral? = ast.arena.expr(argExprID),
                      case let .functionType(declared) = sema.types.kind(of: signature.parameterTypes[paramIndex]),
                      case let .typeParam(parameter) = sema.types.kind(of: declared.returnType)
                else {
                    continue
                }
                let substituted = substitutedLambdaReturnType(
                    for: argExprID,
                    declaredReturnParameter: parameter,
                    signature: signature,
                    binding: binding,
                    sema: sema
                ) ?? declared.returnType
                result[argExprID] = (parameter.symbol, substituted)
            }
        }
        return result
    }

    /// The type the call site substitutes for the erased return type
    /// parameter — `Int?` in `invokeBlock { uncheckedCast<Int?>() }` — or
    /// the lambda's own inferred return type when the binding lacks a
    /// positional argument for the parameter.
    private static func substitutedLambdaReturnType(
        for lambdaExprID: ExprID,
        declaredReturnParameter: TypeParamType,
        signature: FunctionSignature,
        binding: CallBinding,
        sema: SemaModule
    ) -> TypeID? {
        if binding.substitutedTypeArguments.count == signature.typeParameterSymbols.count,
           let index = signature.typeParameterSymbols.firstIndex(of: declaredReturnParameter.symbol) {
            return binding.substitutedTypeArguments[index]
        }
        if let boundType = sema.bindings.exprType(for: lambdaExprID),
           case let .functionType(functionType) = sema.types.kind(of: boundType) {
            return functionType.returnType
        }
        return nil
    }

    private static func callArguments(of exprID: ExprID, ast: ASTModule) -> [CallArgument]? {
        switch ast.arena.expr(exprID) {
        case let .call(_, _, args, _),
             let .memberCall(_, _, _, args, _),
             let .safeMemberCall(_, _, _, args, _):
            args
        default:
            nil
        }
    }
}
