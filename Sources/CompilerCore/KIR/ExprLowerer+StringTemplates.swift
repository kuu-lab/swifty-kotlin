extension ExprLowerer {
    func lowerStringTemplateExpr(
        parts: [StringTemplatePart],
        exprID: ExprID,
        stringType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // A template whose interpolated parts are all compile-time constants
        // is itself a compile-time constant on the JVM — folded into one
        // interned literal, so identical non-const initializers such as
        // `object A { val s = "1234$constA" }` / `object B { ... }` share the
        // same string instance (`A.s === B.s`). Mirror the `+` fold in
        // CallLowerer+Operators: `compileTimeConstantRef` resolves `const
        // val` reads only, so a plain `val`/`var` or any effectful part keeps
        // the runtime `__kk_string_concat_flat` path below (KUU-3180).
        var collector = driver.constantCollector
        collector.resolvedConstant = { constExprID in
            self.driver.callLowerer.compileTimeConstantRef(constExprID, ast: ast, sema: sema)
        }
        if let foldedText = collector.constantStringConcatOperandText(
            exprID, ast: ast, sema: sema, interner: interner
        ) {
            let foldedSymbol = interner.intern(foldedText)
            let literalID = arena.appendExpr(.stringLiteral(foldedSymbol), type: stringType)
            instructions.append(.constValue(result: literalID, value: .stringLiteral(foldedSymbol)))
            return literalID
        }
        var partIDs: [KIRExprID] = []
        for part in parts {
            switch part {
            case let .literal(interned):
                let partID = arena.appendExpr(.stringLiteral(interned), type: stringType)
                instructions.append(.constValue(result: partID, value: .stringLiteral(interned)))
                partIDs.append(partID)
            case let .expression(exprID):
                let lowered = lowerExpr(
                    exprID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                // Bodies Sema never visits (a stdlib delegate's callback
                // lambda, for instance) have no bound expression type; the
                // lowered KIR type is the only description of the value and
                // must still drive the string conversion.
                let exprType = sema.bindings.exprTypes[exprID] ?? arena.exprType(lowered)
                if let exprType, exprType != stringType {
                    // See CallLowerer.emitAnyToStringWithNullGuard for why nullable
                    // Float?/Double?/ULong? need an explicit null guard before
                    // kk_any_to_string (their null-sentinel bit pattern coincides
                    // with a legitimate in-range value for those tags).
                    let converted = driver.callLowerer.emitAnyToStringWithNullGuard(
                        valueID: lowered,
                        valueType: exprType,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    partIDs.append(converted)
                } else {
                    partIDs.append(lowered)
                }
            }
        }
        if partIDs.isEmpty {
            let emptyStr = interner.intern("")
            let id = arena.appendExpr(.stringLiteral(emptyStr), type: stringType)
            instructions.append(.constValue(result: id, value: .stringLiteral(emptyStr)))
            return id
        }
        var accumulated = partIDs[0]
        for i in 1 ..< partIDs.count {
            let concatResult = arena.appendTemporary(type: stringType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("__kk_string_concat_flat"),
                arguments: [accumulated, partIDs[i]],
                result: concatResult,
                canThrow: false,
                thrownResult: nil
            ))
            accumulated = concatResult
        }
        return accumulated
    }
}
