extension JVMFunctionBuilder {
    func numericFloorDiv(_ receiver: ExprID, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        guard args.count == 1, !args[0].isSpread,
              args[0].label.map({ context.interner.resolve($0) }) == nil
                || args[0].label.map({ context.interner.resolve($0) }) == "other",
              let rawType = evaluatedOperands[receiver]?.type ?? (try? program.expressionType(receiver)),
              let sourceType = rawType.numericCarrier,
              let argumentType = (try? program.expressionType(args[0].expr))?.numericCarrier
        else { return nil }
        let signed: Set<JVMValueType> = [.byte, .short, .int, .long]
        guard signed.contains(sourceType), signed.contains(argumentType) else { return nil }

        if let selected = program.sema.bindings.callBinding(for: id)?.chosenCallee
            ?? program.sema.bindings.identifierSymbol(for: id)
        {
            guard let symbol = program.sema.symbols.symbol(selected) else { return nil }
            let primitiveName: String? = switch sourceType {
            case .byte: "Byte"
            case .short: "Short"
            case .int: "Int"
            case .long: "Long"
            default: nil
            }
            let path = symbol.fqName.map(context.interner.resolve)
            let isBuiltin = path == ["kotlin", "floorDiv"]
                || primitiveName.map { path == ["kotlin", $0, "floorDiv"] } == true
            guard isBuiltin,
                  symbol.declSite.map({ context.sourceManager.origin(of: $0.start.file) != .user }) ?? true
            else { return nil }
        }

        let type = try numericType(sourceType, argumentType)
        let left = try convert(requireValue(receiver), to: type)
        let right = try convert(requireValue(args[0].expr), to: type)
        return JVMIntrinsicResult(value: try jdkCall(
            "java/lang/Math", "floorDiv", [type, type], type, arguments: [left, right]
        ))
    }
}
