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

    /// Boxes a primitive value flowing out of an erased return position.
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
        guard let boxCallee = erasedReturnBoxCallee(
            returnType,
            returnsErasedGeneric: returnsErasedGeneric,
            sema: sema,
            interner: interner
        ) else {
            return value
        }
        return emitNonThrowingCall(
            callee: boxCallee,
            arg: value,
            resultType: sema.types.anyType,
            arena: arena,
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
                  for: sema.types.kind(of: returnType),
                  requireNonNull: true
              )
        else {
            return nil
        }
        return callee
    }
}

extension KIRLoweringContext {
    /// True when the lambda literal `exprID` is a call argument whose declared
    /// parameter type returns a type parameter.
    func lambdaReturnsErasedGeneric(
        for exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> Bool {
        if erasedGenericReturnLambdaExprIDs == nil {
            erasedGenericReturnLambdaExprIDs = Self.collectErasedGenericReturnLambdas(ast: ast, sema: sema)
        }
        return erasedGenericReturnLambdaExprIDs?.contains(exprID) ?? false
    }

    private static func collectErasedGenericReturnLambdas(
        ast: ASTModule,
        sema: SemaModule
    ) -> Set<ExprID> {
        var result: Set<ExprID> = []
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
                      case .typeParam = sema.types.kind(of: declared.returnType)
                else {
                    continue
                }
                result.insert(argExprID)
            }
        }
        return result
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
