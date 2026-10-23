extension KIRLoweringDriver {
    func lowerKTypeExpr(
        for type: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.intType
        let stringType = sema.types.stringType
        var initializedTypeParameters: Set<SymbolID> = []

        func integer(_ value: Int64) -> KIRExprID {
            let expr = arena.appendExpr(.intLiteral(value), type: intType)
            instructions.append(.constValue(result: expr, value: .intLiteral(value)))
            return expr
        }

        func string(_ value: String) -> KIRExprID {
            let literal = interner.intern(value)
            let expr = arena.appendExpr(.stringLiteral(literal), type: stringType)
            instructions.append(.constValue(result: expr, value: .stringLiteral(literal)))
            return expr
        }

        func list(_ elements: [KIRExprID]) -> KIRExprID {
            makeReflectionArgumentList(
                elements,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        func makeTypeTokenExpr(for type: TypeID) -> KIRExprID {
            if case let .typeParam(typeParameter) = sema.types.kind(of: type) {
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParameter.symbol)
                if let captured = ctx.localValue(for: tokenSymbol) { return captured }
                let tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
                instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
                return tokenExpr
            }
            return integer(RuntimeTypeCheckToken.encode(type: type, sema: sema, interner: interner))
        }

        func makeNameHintExpr(for type: TypeID) -> KIRExprID {
            guard let name = RuntimeTypeCheckToken.qualifiedName(of: type, sema: sema, interner: interner) else {
                return integer(0)
            }
            return string(name)
        }

        func makeNullabilityExpr(for type: TypeID) -> KIRExprID {
            if case let .typeParam(parameter) = sema.types.kind(of: type),
               parameter.nullability != .nullable,
               sema.symbols.symbol(parameter.symbol)?.flags.contains(.reifiedTypeParameter) == true {
                let token = makeTypeTokenExpr(for: type)
                let mask = integer(RuntimeTypeCheckToken.nullableFlag)
                let nullable = arena.appendTemporary(type: intType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_bitwise_and"),
                    arguments: [token, mask],
                    result: nullable,
                    canThrow: false,
                    thrownResult: nil
                ))
                return nullable
            }

            let isNullable: Int64 = switch sema.types.kind(of: type) {
            case .nullableUnit:
                1
            case let .primitive(_, nullability), let .stringStruct(nullability), let .any(nullability),
                 let .nothing(nullability):
                nullability == .nullable ? 1 : 0
            case let .classType(classType):
                classType.nullability == .nullable ? 1 : 0
            case let .typeParam(typeParameter):
                typeParameter.nullability == .nullable ? 1 : 0
            case let .kClassType(kClassType):
                kClassType.nullability == .nullable ? 1 : 0
            case let .functionType(functionType):
                functionType.nullability == .nullable ? 1 : 0
            default:
                0
            }
            return integer(isNullable)
        }

        func typeParameterVarianceOrdinal(for parameter: SymbolID) -> Int64 {
            guard let owner = sema.symbols.parentSymbol(for: parameter),
                  let ownerInfo = sema.symbols.symbol(owner),
                  [.class, .interface, .object, .enumClass, .annotationClass].contains(ownerInfo.kind)
            else {
                return 0
            }
            let parameters = sema.types.nominalTypeParameterSymbols(for: owner)
            guard let index = parameters.firstIndex(of: parameter),
                  sema.types.nominalTypeParameterVariances(for: owner).indices.contains(index)
            else {
                return 0
            }
            switch sema.types.nominalTypeParameterVariances(for: owner)[index] {
            case .invariant: return 0
            case .in: return 1
            case .out: return 2
            }
        }

        func makeTypeParameterClassifier(_ typeParameter: TypeParamType) -> KIRExprID {
            let symbol = typeParameter.symbol
            let info = sema.symbols.symbol(symbol)
            let identity = integer(Int64(symbol.rawValue))
            let name = string(info.map { interner.resolve($0.name) } ?? "T")
            let variance = integer(typeParameterVarianceOrdinal(for: symbol))
            let isReified = integer(info?.flags.contains(.reifiedTypeParameter) == true ? 1 : 0)
            let classifier = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("__kk_ktypeparameter_create"),
                arguments: [identity, name, variance, isReified],
                result: classifier,
                canThrow: false,
                thrownResult: nil
            ))

            if initializedTypeParameters.insert(symbol).inserted {
                let declaredBounds = sema.symbols.typeParameterUpperBounds(for: symbol)
                let bounds = declaredBounds.isEmpty ? [sema.types.nullableAnyType] : declaredBounds
                let boundTypes = bounds.map { lowerKTypeExpr(for: $0) }
                let boundsList = list(boundTypes)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_ktypeparameter_set_upper_bounds"),
                    arguments: [classifier, boundsList],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return classifier
        }

        func lowerKTypeExpr(for type: TypeID) -> KIRExprID {
            func enclosingTypeArgumentsInReflectionOrder(for classType: ClassType) -> [TypeArg] {
                guard !classType.enclosingTypeArgs.isEmpty else { return [] }

                var enclosingOwners: [SymbolID] = []
                var parent = sema.symbols.parentSymbol(for: classType.classSymbol)
                while let owner = parent, let ownerInfo = sema.symbols.symbol(owner) {
                    if [.class, .interface, .object, .enumClass, .annotationClass].contains(ownerInfo.kind) {
                        enclosingOwners.append(owner)
                    }
                    parent = sema.symbols.parentSymbol(for: owner)
                }

                var remainingCount = classType.enclosingTypeArgs.count
                var result: [TypeArg] = []
                for owner in enclosingOwners {
                    let parameterCount = sema.types.nominalTypeParameterSymbols(for: owner).count
                    guard parameterCount > 0, parameterCount <= remainingCount else { continue }
                    let start = remainingCount - parameterCount
                    result.append(contentsOf: classType.enclosingTypeArgs[start ..< remainingCount])
                    remainingCount = start
                }
                if remainingCount > 0 {
                    result.append(contentsOf: classType.enclosingTypeArgs[..<remainingCount])
                }
                return result
            }

            func lowerProjection(_ argument: TypeArg) -> KIRExprID {
                let varianceOrdinal: Int64
                let projectedType: KIRExprID
                switch argument {
                case .star:
                    varianceOrdinal = -1
                    projectedType = integer(0)
                case let .invariant(argumentType):
                    varianceOrdinal = 2
                    projectedType = lowerKTypeExpr(for: argumentType)
                case let .out(argumentType):
                    varianceOrdinal = 1
                    projectedType = lowerKTypeExpr(for: argumentType)
                case let .in(argumentType):
                    varianceOrdinal = 0
                    projectedType = lowerKTypeExpr(for: argumentType)
                }
                let variance = integer(varianceOrdinal)
                let result = arena.appendTemporary(type: sema.types.anyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_ktypeprojection_create"),
                    arguments: [projectedType, variance],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }

            let nonNullableType = sema.types.makeNonNullable(type)
            let typeParameter: TypeParamType? = {
                guard case let .typeParam(parameter) = sema.types.kind(of: nonNullableType),
                      sema.symbols.symbol(parameter.symbol)?.flags.contains(.reifiedTypeParameter) != true
                else {
                    return nil
                }
                return parameter
            }()
            let tokenExpr = makeTypeTokenExpr(for: nonNullableType)
            if typeParameter == nil {
                callLowerer.emitClassLiteralMetadataRegistration(
                    classRefTargetType: nonNullableType,
                    typeTokenExpr: tokenExpr,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }

            let typeArguments: [TypeArg]
            switch sema.types.kind(of: nonNullableType) {
            case let .classType(classType):
                typeArguments = classType.args + enclosingTypeArgumentsInReflectionOrder(for: classType)
            case let .kClassType(kClassType):
                typeArguments = [.invariant(kClassType.argument)]
            case let .functionType(functionType):
                var argumentTypes = functionType.contextReceivers
                if let receiver = functionType.receiver {
                    argumentTypes.append(receiver)
                }
                argumentTypes.append(contentsOf: functionType.params)
                argumentTypes.append(functionType.returnType)
                typeArguments = argumentTypes.map(TypeArg.invariant)
            default:
                typeArguments = []
            }
            let argumentRaws = typeArguments.map(lowerProjection)
            let argumentList = list(argumentRaws)
            let nullability = makeNullabilityExpr(for: type)
            let ktype = arena.appendTemporary(type: sema.types.anyType)

            if let typeParameter {
                let classifier = makeTypeParameterClassifier(typeParameter)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_ktype_create"),
                    arguments: [classifier, argumentList, nullability],
                    result: ktype,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_typeof"),
                    arguments: [tokenExpr, makeNameHintExpr(for: type), argumentList, nullability],
                    result: ktype,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return ktype
        }

        return lowerKTypeExpr(for: type)
    }
}
