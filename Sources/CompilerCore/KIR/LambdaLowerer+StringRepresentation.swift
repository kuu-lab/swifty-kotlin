extension LambdaLowerer {
    func emitFunctionDescription(
        value: KIRExprID,
        description: String,
        identity: Bool,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let text = interner.intern(description)
        let textExpr = arena.appendExpr(.stringLiteral(text), type: sema.types.stringType)
        instructions.append(.constValue(result: textExpr, value: .stringLiteral(text)))
        let flag: Int64 = identity ? 1 : 0
        let flagExpr = arena.appendExpr(.intLiteral(flag), type: sema.types.intType)
        instructions.append(.constValue(result: flagExpr, value: .intLiteral(flag)))
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_function_set_description"),
            arguments: [value, textExpr, flagExpr],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
    }

    func functionReferenceDescription(
        name: InternedString,
        type: TypeID,
        targetSymbol: SymbolID?,
        sema: SemaModule,
        interner: StringInterner
    ) -> String {
        guard case let .functionType(function) = sema.types.kind(of: type) else {
            return "fun \(interner.resolve(name))()"
        }
        let signature = targetSymbol.flatMap { sema.symbols.functionSignature(for: $0) }
        let receiver = signature?.receiverType ?? targetSymbol.flatMap {
            sema.symbols.parentSymbol(for: $0)
        }.flatMap { owner -> TypeID? in
            guard let symbol = sema.symbols.symbol(owner),
                  symbol.kind == .class || symbol.kind == .interface || symbol.kind == .enumClass
            else { return nil }
            return sema.types.make(.classType(ClassType(classSymbol: owner, args: [], nullability: .nonNull)))
        }
        let receiverText = receiver.map { reflectionTypeName($0, sema: sema, interner: interner) + "." } ?? ""
        let params = (signature?.parameterTypes ?? function.params)
            .map { reflectionTypeName($0, sema: sema, interner: interner) }.joined(separator: ", ")
        let result = reflectionTypeName(signature?.returnType ?? function.returnType, sema: sema, interner: interner)
        let prefix = function.isSuspend ? "suspend fun " : "fun "
        return "\(prefix)\(receiverText)\(interner.resolve(name))(\(params)): \(result)"
    }

    private func reflectionTypeName(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> String {
        let suffix = sema.types.nullability(of: type) == .nullable ? "?" : ""
        switch sema.types.kind(of: type) {
        case let .classType(cls):
            let base = RuntimeTypeCheckToken.qualifiedName(of: type, sema: sema, interner: interner)
                ?? sema.types.displayName(of: type, symbols: sema.symbols, interner: interner)
            let args = cls.args.map { arg -> String in
                switch arg {
                case let .invariant(t): reflectionTypeName(t, sema: sema, interner: interner)
                case let .in(t): "in " + reflectionTypeName(t, sema: sema, interner: interner)
                case let .out(t): "out " + reflectionTypeName(t, sema: sema, interner: interner)
                case .star: "*"
                }
            }
            return base + (args.isEmpty ? "" : "<" + args.joined(separator: ", ") + ">") + suffix
        case .typeParam:
            return sema.types.displayName(of: type, symbols: sema.symbols, interner: interner)
        case let .functionType(fn):
            let params = fn.params.map { reflectionTypeName($0, sema: sema, interner: interner) }.joined(separator: ", ")
            let receiver = fn.receiver.map { reflectionTypeName($0, sema: sema, interner: interner) + "." } ?? ""
            let text = (fn.isSuspend ? "suspend " : "") + receiver + "(\(params)) -> " + reflectionTypeName(fn.returnType, sema: sema, interner: interner)
            return suffix.isEmpty ? text : "(\(text))?"
        default:
            return (RuntimeTypeCheckToken.qualifiedName(of: type, sema: sema, interner: interner)
                ?? sema.types.displayName(of: sema.types.makeNonNullable(type), symbols: sema.symbols, interner: interner)) + suffix
        }
    }
}
