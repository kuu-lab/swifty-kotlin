extension OverloadResolver {
    /// Preserve Java's Boolean! value constraint and captured key argument.
    /// This applies only to the compiler-owned platform signature.
    func javaCollectionsMapArgument(
        fqName: [InternedString], signature: FunctionSignature, call: CallExpr, ctx: SemaModule
    ) -> (compatible: Bool, replacement: TypeID?) {
        guard signature.parameterTypes.count == 1,
              case let .classType(parameter) = ctx.types.kind(of: signature.parameterTypes[0]),
              parameter.args.count == 2,
              case let .out(value) = parameter.args[1],
              case .primitive(.boolean, .platformType) = ctx.types.kind(of: value),
              fqName.count == 4, let interner = ctx.interner,
              fqName.map({ interner.resolve($0) }) == ["java", "util", "Collections", "newSetFromMap"]
        else { return (true, nil) }
        guard call.args.count == 1 else { return (false, nil) }
        let argumentType = call.args[0].type
        if case .nothing = ctx.types.kind(of: argumentType) { return (true, nil) }
        var pending = [argumentType]
        var visited: Set<TypeID> = []
        while let current = pending.popLast() {
            guard visited.insert(current).inserted else { continue }
            switch ctx.types.kind(of: current) {
            case let .typeParam(typeParameter):
                if let capture = typeParameter.capture {
                    pending.append(capture.upper)
                } else {
                    pending.append(contentsOf: ctx.symbols.typeParameterUpperBounds(for: typeParameter.symbol))
                }
            case let .intersection(parts):
                pending.append(contentsOf: parts)
            case let .classType(argument):
                guard let mapArgs = ctx.types.liftedNominalSupertypeArgs(
                    from: argument.classSymbol, childArgs: argument.args, to: parameter.classSymbol
                ), mapArgs.count == 2 else { continue }
                let mapValue: TypeID
                switch mapArgs[1] {
                case let .invariant(type), let .out(type): mapValue = type
                case .in, .star: continue
                }
                // Do not approximate a Boolean-bounded value parameter: Java
                // rejects it, even though Boolean and Boolean? are both valid.
                guard case .primitive(.boolean, _) = ctx.types.kind(of: mapValue) else { continue }
                if case let .invariant(key) = mapArgs[0] {
                    if !call.explicitTypeArgs.isEmpty,
                       case let .typeParam(typeParameter) = ctx.types.kind(of: key), typeParameter.capture != nil {
                        return (false, nil)
                    }
                    return (true, nil)
                }
                guard call.explicitTypeArgs.isEmpty,
                      let keyParameter = ctx.types.nominalTypeParameterSymbols(for: parameter.classSymbol).first
                else { return (false, nil) }
                let lower: TypeID
                let upper: TypeID
                let writeForbidden: Bool
                switch mapArgs[0] {
                case let .out(type):
                    (lower, upper) = (ctx.types.nothingType, type)
                    writeForbidden = true
                case let .in(type):
                    (lower, upper) = (type, ctx.types.nullableAnyType)
                    writeForbidden = false
                case .star:
                    (lower, upper) = (ctx.types.nothingType, ctx.types.nullableAnyType)
                    writeForbidden = true
                case .invariant: return (true, nil)
                }
                let key = ctx.types.makeCapturedType(
                    parameter: keyParameter,
                    lower: lower,
                    upper: upper,
                    writeForbidden: writeForbidden
                )
                return (true, ctx.types.make(.classType(ClassType(
                    classSymbol: parameter.classSymbol, args: [.invariant(key), mapArgs[1]],
                    nullability: ctx.types.nullability(of: argumentType)
                ))))
            default: continue
            }
        }
        return (false, nil)
    }
}
