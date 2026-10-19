extension DeclTypeChecker {
    func contextualConstructorThisArgumentReceivers(
        args: [CallArgument],
        argTypes: [TypeID],
        candidates: [SymbolID],
        targetType: TypeID?,
        callRange: SourceRange,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> [SymbolID: [Int: (type: TypeID, symbol: SymbolID?)]] {
        let sema = ctx.sema
        let receivers = constructorThisReceiverTower(ctx: ctx, locals: locals)
        guard !receivers.isEmpty else { return [:] }

        let callArgs = zip(args, argTypes).map { argument, type in
            CallArg.source(argument, type: type, callRange: callRange, ast: ctx.ast)
        }
        var result: [SymbolID: [Int: (type: TypeID, symbol: SymbolID?)]] = [:]
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let parameterMapping = ctx.resolver.buildParameterMapping(
                      signature: signature,
                      callArgs: callArgs,
                      symbols: sema.symbols,
                      typeSystem: sema.types
                  )
            else { continue }

            for (argumentIndex, argument) in args.enumerated() {
                guard !argument.isSpread,
                      case .thisRef(label: nil, _) = ctx.ast.arena.expr(argument.expr),
                      let parameterIndex = parameterMapping[argumentIndex],
                      signature.parameterTypes.indices.contains(parameterIndex)
                else { continue }

                let parameterType = instantiatedConstructorParameterType(
                    signature.parameterTypes[parameterIndex],
                    candidate: candidate,
                    targetType: targetType,
                    ctx: ctx
                )
                guard let receiver = receivers.first(where: { receiver in
                    sema.types.isSubtype(
                        sema.types.makeNonNullable(receiver.type),
                        sema.types.makeNonNullable(parameterType)
                    )
                }) else { continue }
                result[candidate, default: [:]][argumentIndex] = receiver
            }
        }
        return result
    }

    private func constructorThisReceiverTower(
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> [(type: TypeID, symbol: SymbolID?)] {
        let sema = ctx.sema
        let thisName = ctx.interner.intern("this")
        var receiverValues: [(type: TypeID, symbol: SymbolID?)] = []
        var seenTypes: Set<TypeID> = []

        func appendReceiver(_ type: TypeID, symbol: SymbolID?) {
            guard type != sema.types.errorType, seenTypes.insert(type).inserted else { return }
            receiverValues.append((type, symbol))

            guard let owner = driver.helpers.nominalSymbol(of: type, types: sema.types),
                  let companion = sema.symbols.companionObjectSymbol(for: owner)
            else { return }
            let companionType = sema.symbols.propertyType(for: companion)
                ?? sema.types.make(.classType(ClassType(
                    classSymbol: companion,
                    args: [],
                    nullability: .nonNull
                )))
            guard seenTypes.insert(companionType).inserted else { return }
            receiverValues.append((companionType, companion))
        }

        if let thisLocal = locals[thisName] {
            appendReceiver(thisLocal.type, symbol: thisLocal.symbol)
        }
        if let implicitReceiverType = ctx.implicitReceiverType {
            appendReceiver(implicitReceiverType, symbol: nil)
        }
        for receiver in ctx.implicitReceiverStack.reversed() {
            appendReceiver(receiver.type, symbol: receiver.symbol)
        }
        for receiver in ctx.outerReceiverTypes.reversed() {
            guard let symbol = receiver.symbol else { continue }
            appendReceiver(receiver.type, symbol: symbol)
        }
        return receiverValues
    }

    private func instantiatedConstructorParameterType(
        _ parameterType: TypeID,
        candidate: SymbolID,
        targetType: TypeID?,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        guard let targetType,
              let owner = sema.symbols.parentSymbol(for: candidate),
              case let .classType(ownerClassType) = sema.types.kind(of: targetType),
              ownerClassType.classSymbol == owner
        else { return parameterType }

        let ownerParameters = sema.types.allTypeParameterSymbols(for: owner)
        let ownerArguments = sema.types.allTypeArguments(for: ownerClassType)
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(ownerParameters)
        var substitution: [TypeVarID: TypeID] = [:]
        for (parameter, argument) in zip(ownerParameters, ownerArguments) {
            guard let variable = typeVarBySymbol[parameter] else { continue }
            switch argument {
            case let .invariant(type), let .in(type), let .out(type):
                substitution[variable] = type
            case .star:
                continue
            }
        }
        return sema.types.substituteTypeParameters(
            in: parameterType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }
}
