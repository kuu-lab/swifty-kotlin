extension OverloadResolver {
    /// Java's List parameter accepts either Kotlin list view, while its type
    /// argument remains invariant. Model the mapped interface for inference
    /// without changing the runtime value or relaxing the bundled signature.
    func javaCheckedListCall(
        _ call: CallExpr, symbol: SemanticSymbol, signature: FunctionSignature, ctx: SemaModule
    ) -> CallExpr {
        guard let interner = ctx.interner,
              symbol.fqName.map({ interner.resolve($0) }) == ["java", "util", "Collections", "checkedList"],
              ctx.bundledIndex.contains(ownerFQName: Array(symbol.fqName.dropLast()), name: symbol.name, arity: 2),
              signature.parameterTypes.count == 2, call.args.count == 2,
              case let .classType(parameter) = ctx.types.kind(of: signature.parameterTypes[0]),
              let mutableList = ctx.symbols.lookup(fqName: ["kotlin", "collections", "MutableList"].map(interner.intern)),
              parameter.classSymbol == mutableList,
              let list = ctx.symbols.lookup(fqName: ["kotlin", "collections", "List"].map(interner.intern))
        else { return call }
        let originalType = call.args[0].type
        var pending = [originalType]
        var visited: Set<TypeID> = []
        while let current = pending.popLast() {
            guard visited.insert(current).inserted else { continue }
            switch ctx.types.kind(of: current) {
            case let .typeParam(parameter):
                if let capture = parameter.capture {
                    pending.append(capture.upper)
                } else {
                    pending.append(contentsOf: ctx.symbols.typeParameterUpperBounds(for: parameter.symbol))
                }
            case let .intersection(parts):
                pending.append(contentsOf: parts)
            case let .classType(argument):
                guard let arguments = ctx.types.liftedNominalSupertypeArgs(from: argument, to: list),
                      arguments.count == 1 else { continue }
                let mapped = ctx.types.make(.classType(ClassType(
                    classSymbol: mutableList, args: arguments, nullability: ctx.types.nullability(of: originalType)
                )))
                return call.replacingArgumentTypes([0: mapped])
            default:
                continue
            }
        }
        return call
    }
}
