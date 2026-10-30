extension LambdaLowerer {
    func emitLambdaEnclosingClassMetadata(
        exprID: ExprID,
        value: KIRExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard let fileID = ast.arena.exprRange(exprID)?.start.file,
              let enclosingClassName = driver.ctx.lambdaEnclosingClassNamesByFileID[fileID]
        else {
            return
        }

        let name = interner.intern(enclosingClassName)
        let nameExpr = arena.appendExpr(.stringLiteral(name), type: sema.types.stringType)
        instructions.append(.constValue(result: nameExpr, value: .stringLiteral(name)))
        instructions.append(.call(
            callee: interner.intern("__kk_function_set_enclosing_class"),
            arguments: [value, nameExpr],
            result: nil,
            canThrow: false
        ))
    }

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
            callee: interner.intern("__kk_function_set_description"),
            arguments: [value, textExpr, flagExpr],
            result: nil,
            canThrow: false
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
        // kotlin-reflect renders a constructor reference with the `<init>`
        // name backtick-escaped and no receiver prefix for an ordinary
        // class (`fun `<init>`(kotlin.Int): B`), while an `inner class`
        // constructor keeps its outer-class dispatch receiver
        // (`fun Outer.`<init>`(): Outer.Inner`) (KUU-3810).
        let isConstructor = targetSymbol.flatMap { sema.symbols.symbol($0)?.kind } == .constructor
        let innerConstructorOuterClass = targetSymbol
            .flatMap { sema.symbols.parentSymbol(for: $0) }
            .flatMap { owner -> SymbolID? in
                guard sema.symbols.symbol(owner)?.flags.contains(.innerClass) == true else {
                    return nil
                }
                return sema.symbols.parentSymbol(for: owner)
            }
        let receiver = signature?.receiverType ?? targetSymbol.flatMap {
            sema.symbols.parentSymbol(for: $0)
        }.flatMap { owner -> TypeID? in
            guard let symbol = sema.symbols.symbol(owner),
                  symbol.kind == .class || symbol.kind == .interface || symbol.kind == .enumClass
            else { return nil }
            return sema.types.make(.classType(ClassType(classSymbol: owner, args: [], nullability: .nonNull)))
        }
        let receiverText: String
        if isConstructor {
            receiverText = innerConstructorOuterClass.map {
                reflectionTypeName(
                    sema.types.make(.classType(ClassType(classSymbol: $0, args: [], nullability: .nonNull))),
                    sema: sema, interner: interner
                ) + "."
            } ?? ""
        } else {
            receiverText = receiver.map { reflectionTypeName($0, sema: sema, interner: interner) + "." } ?? ""
        }
        let params = (signature?.parameterTypes ?? function.params)
            .map { reflectionTypeName($0, sema: sema, interner: interner) }.joined(separator: ", ")
        let result = reflectionTypeName(signature?.returnType ?? function.returnType, sema: sema, interner: interner)
        let prefix = function.isSuspend ? "suspend fun " : "fun "
        let renderedName = isConstructor ? "`\(interner.resolve(name))`" : interner.resolve(name)
        return "\(prefix)\(receiverText)\(renderedName)(\(params)): \(result)"
    }

    func functionTypeDescription(
        _ function: FunctionType,
        sema: SemaModule,
        interner: StringInterner
    ) -> String {
        let params = function.params
            .map { reflectionTypeName($0, sema: sema, interner: interner) }
            .joined(separator: ", ")
        let receiver = function.receiver
            .map { reflectionTypeName($0, sema: sema, interner: interner) + "." } ?? ""
        let prefix = function.isSuspend ? "suspend " : ""
        let result = reflectionTypeName(function.returnType, sema: sema, interner: interner)
        return "\(prefix)\(receiver)(\(params)) -> \(result)"
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
