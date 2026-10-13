extension CallTypeChecker {
    struct SamFactoryShape {
        let argumentType: TypeID
        let functionType: FunctionType
    }

    /// Factory applicability is determined from argument mapping and callable
    /// input shape. Lambda body results are checked only after overload selection.
    func samFactoryShapes(
        _ candidates: [SymbolID],
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        explicitTypeArgs: [TypeID]
    ) -> [SymbolID: SamFactoryShape] {
        // Only a single argument can compete with the synthetic SAM constructor.
        guard args.count == 1 else { return [:] }
        let sema = ctx.sema
        let argument = args[0]
        var shapes: [SymbolID: SamFactoryShape] = [:]
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let mapping = parameterMappingForCallArguments(args, in: signature, ctx: ctx),
                  let parameterIndex = mapping[0],
                  parameterIndex < signature.parameterTypes.count
            else { continue }
            let parameter = applyExplicitTypeArgs(
                to: signature.parameterTypes[parameterIndex], signature: signature,
                candidate: candidate, explicitTypeArgs: explicitTypeArgs, sema: sema
            )
            guard let function = callableArgumentFunctionType(parameter, ctx: ctx) else { continue }
            var argumentType = parameter
            switch ctx.ast.arena.expr(argument.expr) {
            case let .lambdaLiteral(params, _, _, _):
                guard params.isEmpty ? function.params.count <= 1 : params.count == function.params.count else { continue }
                if let annotations = driver.exprChecker.resolveLambdaParamAnnotations(
                    argument.expr, ctx: ctx, paramCount: function.params.count
                ) {
                    guard zip(annotations, function.params).allSatisfy({ annotation, declared in
                        guard let annotation else { return true }
                        return driver.exprChecker.lambdaAnnotationIsCompatible(
                            annotated: annotation, declared: declared,
                            expectedTypeIsSourceDeclared: true, sema: sema
                        )
                    }) else { continue }
                    let annotatedFunction = sema.types.make(.functionType(FunctionType(
                        contextReceivers: function.contextReceivers,
                        receiver: function.receiver,
                        params: zip(annotations, function.params).map { $0 ?? $1 },
                        returnType: function.returnType,
                        isSuspend: function.isSuspend,
                        nullability: function.nullability,
                        throws: function.throws
                    )))
                    if case .functionType = sema.types.kind(of: parameter) {
                        argumentType = annotatedFunction
                    } else {
                        // Preserve the nominal SAM argument while propagating its
                        // annotated inputs into the factory's type-variable bounds.
                        let typeVars = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                        let constraints = ctx.resolver.decomposeSubtypeConstraint(
                            subtype: annotatedFunction, supertype: sema.types.make(.functionType(function)),
                            typeVarBySymbol: typeVars, typeSystem: sema.types, blameRange: range
                        )
                        let solution = ConstraintSolver().solve(
                            vars: ctx.resolver.usedTypeVariables(from: constraints),
                            constraints: constraints, typeSystem: sema.types
                        )
                        guard solution.isSuccess else { continue }
                        argumentType = sema.types.substituteTypeParameters(
                            in: parameter, substitution: solution.substitution, typeVarBySymbol: typeVars
                        )
                    }
                }
            case .callableRef:
                guard callableReferenceAcceptsArgumentType(
                    argument.expr, parameter: parameter, ctx: ctx, locals: locals
                ) else { continue }
            default:
                continue
            }
            let probe = ctx.resolver.probeCall(
                candidates: [candidate],
                call: CallExpr(
                    range: range, calleeName: calleeName,
                    args: [CallArg(label: argument.label, isSpread: argument.isSpread, isTrailingLambda: argument.isTrailingLambda, type: argumentType)],
                    explicitTypeArgs: explicitTypeArgs
                ),
                expectedType: nil,
                implicitReceiverType: ctx.implicitReceiverType,
                ctx: sema
            )
            if !probe.viableCandidates.isEmpty {
                shapes[candidate] = SamFactoryShape(argumentType: argumentType, functionType: function)
            }
        }
        return shapes
    }

    /// Return-type refinement remains on the ordinary resolver path when the
    /// overloads have the same lambda inputs and explicitly opt into refinement.
    func samFactoryAllowsReturnTypeRefinement(
        _ candidates: [SymbolID], shapes: [SymbolID: SamFactoryShape], sema: SemaModule
    ) -> Bool {
        guard let first = candidates.first.flatMap({ shapes[$0]?.functionType }),
              candidates.allSatisfy({ candidate in
                  guard let function = shapes[candidate]?.functionType else { return false }
                  return function.params == first.params && function.receiver == first.receiver
                      && function.contextReceivers == first.contextReceivers && function.isSuspend == first.isSuspend
              })
        else { return false }
        return candidates.contains { candidate in
            sema.symbols.annotations(for: candidate).contains {
                KnownCompilerAnnotation.overloadResolutionByLambdaReturnType.matches($0.annotationFQName)
            }
        }
    }
}
