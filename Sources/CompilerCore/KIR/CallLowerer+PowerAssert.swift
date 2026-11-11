extension CallLowerer {
    /// Lowers a call expression targeted by the `power-assert` plugin.
    /// Captures sub-expression values during evaluation of the first argument
    /// and formats a multi-line diagram string lazily on failure, passing it as
    /// the second (`lazyMessage: () -> Any`) argument to the companion overload.
    func lowerPowerAssertCallExpr(
        _ exprID: ExprID,
        info: PowerAssertCallInfo,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let captureTargetSet = Set(info.captureExprs.map(\.exprID))
        driver.ctx.pushPowerAssertCapture(captureTargetSet)
        let condExprID = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let capturedMap = driver.ctx.popPowerAssertCapture()

        // Deduplicate columns while preserving capture entries
        var uniqueCaptures: [(columnOffset: Int, valueID: KIRExprID, type: TypeID)] = []
        var seenCols: Set<Int> = []
        for cap in info.captureExprs {
            guard let valID = capturedMap[cap.exprID],
                  seenCols.insert(cap.columnOffset).inserted
            else { continue }
            let valType = arena.exprType(valID)
                ?? sema.bindings.exprType(for: cap.exprID)
                ?? sema.types.anyType
            uniqueCaptures.append((cap.columnOffset, valID, valType))
        }

        let stringType = sema.types.stringType
        let emptyLiteral = interner.intern("")
        let msgExpr = arena.appendTemporary(type: stringType)
        let emptyConst = arena.appendExpr(.stringLiteral(emptyLiteral), type: stringType)
        instructions.append(.constValue(result: emptyConst, value: .stringLiteral(emptyLiteral)))
        instructions.append(.copy(from: emptyConst, to: msgExpr))

        // Only evaluate toString() and build the diagram string when the assertion actually fails
        let condType = arena.exprType(condExprID)
            ?? sema.bindings.exprType(for: args[0].expr)
            ?? sema.types.booleanType
        let nonNullCondType = sema.types.makeNonNullable(condType)
        let skipLabel = driver.ctx.makeLoopLabel()
        var emittedGuard = false
        if nonNullCondType == sema.types.booleanType,
           sema.types.nullability(of: condType) == .nonNull
        {
            let trueExpr = arena.appendExpr(.boolLiteral(true), type: sema.types.booleanType)
            instructions.append(.constValue(result: trueExpr, value: .boolLiteral(true)))
            instructions.append(.jumpIfEqual(lhs: condExprID, rhs: trueExpr, target: skipLabel))
            emittedGuard = true
        } else if sema.types.nullability(of: condType) != .nonNull {
            instructions.append(.jumpIfNotNull(value: condExprID, target: skipLabel))
            emittedGuard = true
        }

        let formattedMsgExpr = buildPowerAssertDiagramString(
            callLineText: info.callLineText,
            captures: uniqueCaptures,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        instructions.append(.copy(from: formattedMsgExpr, to: msgExpr))

        if emittedGuard {
            instructions.append(.label(skipLabel))
        }

        // Synthesize lazyMessage: () -> Any/String capturing msgExpr (1 capture)
        let overloadSig = sema.symbols.functionSignature(for: info.messageOverloadCallee)
        let overloadLambdaParamType = overloadSig?.parameterTypes.last
        let expectedFuncType: FunctionType = {
            if let overloadLambdaParamType,
               case let .functionType(fnType) = sema.types.kind(of: overloadLambdaParamType)
            {
                return fnType
            }
            return FunctionType(params: [], returnType: sema.types.anyType, nullability: .nonNull)
        }()
        let lambdaReturnType = expectedFuncType.returnType

        let lambdaName = interner.intern("kk_power_assert_msg_\(exprID.rawValue)")
        let lambdaSymbol = sema.symbols.define(
            kind: .function,
            name: lambdaName,
            fqName: [lambdaName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let msgParamSym = driver.lambdaLowerer.syntheticLambdaCaptureParamSymbol(
            lambdaExprID: exprID,
            captureIndex: 0
        )
        let captureParam = KIRParameter(symbol: msgParamSym, type: stringType)

        var lambdaBody: [KIRInstruction] = [.beginBlock]
        let paramRef = arena.appendExpr(.symbolRef(msgParamSym), type: stringType)
        lambdaBody.append(.constValue(result: paramRef, value: .symbolRef(msgParamSym)))
        let retValue: KIRExprID
        if lambdaReturnType != stringType, lambdaReturnType != sema.types.anyType {
            retValue = boxValueForAnySlot(
                paramRef,
                sourceType: stringType,
                types: sema.types,
                symbols: sema.symbols,
                interner: interner,
                arena: arena,
                resultType: lambdaReturnType,
                into: &lambdaBody
            )
        } else {
            retValue = paramRef
        }
        lambdaBody.append(.returnValue(retValue))
        lambdaBody.append(.endBlock)

        let lambdaDeclID = arena.appendDecl(.function(KIRFunction(
            symbol: lambdaSymbol,
            name: lambdaName,
            params: [captureParam],
            returnType: lambdaReturnType,
            body: lambdaBody,
            isSuspend: false,
            isInline: false
        )))
        driver.ctx.appendGeneratedCallableDecl(lambdaDeclID)

        let lambdaValueType = overloadLambdaParamType ?? sema.types.make(.functionType(expectedFuncType))
        let rawLambdaExpr = arena.appendExpr(.symbolRef(lambdaSymbol), type: lambdaValueType)
        instructions.append(.constValue(result: rawLambdaExpr, value: .symbolRef(lambdaSymbol)))
        driver.ctx.registerCallableValue(
            rawLambdaExpr,
            symbol: lambdaSymbol,
            callee: lambdaName,
            captureArguments: [msgExpr],
            hasClosureParam: false
        )
        arena.registerLambdaCaptureArgs(lambdaSymbol, captureArgs: [msgExpr])

        let overloadIsInline = sema.symbols.symbol(info.messageOverloadCallee)?.flags.contains(.inlineFunction) == true
        let passedLambdaExpr: KIRExprID
        if !overloadIsInline,
           let boxedLambda = driver.lambdaLowerer.materializeEscapingCallableValue(
               lambdaSymbol: lambdaSymbol,
               lambdaName: lambdaName,
               lambdaReturnType: lambdaReturnType,
               functionType: expectedFuncType,
               captureArguments: [msgExpr],
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            passedLambdaExpr = boxedLambda
        } else {
            passedLambdaExpr = rawLambdaExpr
        }

        let overloadSym = sema.symbols.symbol(info.messageOverloadCallee)
        let overloadCalleeName: InternedString = {
            if let ext = sema.symbols.externalLinkName(for: info.messageOverloadCallee), !ext.isEmpty {
                return interner.intern(ext)
            }
            return overloadSym?.name ?? interner.intern("assert")
        }()
        let returnType = overloadSig?.returnType ?? sema.types.unitType
        let resultExpr = arena.appendTemporary(type: returnType)
        instructions.append(.call(
            symbol: info.messageOverloadCallee,
            callee: overloadCalleeName,
            arguments: [condExprID, passedLambdaExpr],
            result: resultExpr,
            canThrow: true
        ))
        if returnType == sema.types.unitType {
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        return resultExpr
    }

    private func buildPowerAssertDiagramString(
        callLineText: String,
        captures: [(columnOffset: Int, valueID: KIRExprID, type: TypeID)],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let stringType = sema.types.stringType
        let sorted = captures.sorted { $0.columnOffset < $1.columnOffset }

        guard !sorted.isEmpty else {
            let textInterned = interner.intern(callLineText)
            let expr = arena.appendExpr(.stringLiteral(textInterned), type: stringType)
            instructions.append(.constValue(result: expr, value: .stringLiteral(textInterned)))
            return expr
        }

        // 1. Line 1: call source text
        // 2. Line 2: vertical pipes beneath each capture column
        let maxCol = sorted.last?.columnOffset ?? 0
        var pipesChars = Array(repeating: Character(" "), count: maxCol + 1)
        for item in sorted where item.columnOffset >= 0 && item.columnOffset < pipesChars.count {
            pipesChars[item.columnOffset] = "|"
        }
        let headerAndPipes = callLineText + "\n" + String(pipesChars) + "\n"

        // Start accumulating result string
        let headerInterned = interner.intern(headerAndPipes)
        var accExpr: KIRExprID = arena.appendExpr(.stringLiteral(headerInterned), type: stringType)
        instructions.append(.constValue(result: accExpr, value: .stringLiteral(headerInterned)))

        // 3. Emit value lines from rightmost column to leftmost so vertical lines don't cross
        let reversed = Array(sorted.enumerated()).reversed()
        let concatCallee = interner.intern("__kk_string_concat_flat")

        for (index, item) in reversed {
            var linePrefixChars = Array(repeating: Character(" "), count: item.columnOffset)
            for earlierIndex in 0 ..< index {
                let col = sorted[earlierIndex].columnOffset
                if col >= 0 && col < linePrefixChars.count {
                    linePrefixChars[col] = "|"
                }
            }
            let prefixStr = String(linePrefixChars)
            if !prefixStr.isEmpty {
                let prefixInterned = interner.intern(prefixStr)
                let prefixExpr = arena.appendExpr(.stringLiteral(prefixInterned), type: stringType)
                instructions.append(.constValue(result: prefixExpr, value: .stringLiteral(prefixInterned)))
                let joined = arena.appendTemporary(type: stringType)
                instructions.append(.call(callee: concatCallee, arguments: [accExpr, prefixExpr], result: joined, canThrow: false))
                accExpr = joined
            }

            let valueStrExpr = emitAnyToStringWithNullGuard(
                valueID: item.valueID,
                valueType: item.type,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let withValue = arena.appendTemporary(type: stringType)
            instructions.append(.call(callee: concatCallee, arguments: [accExpr, valueStrExpr], result: withValue, canThrow: false))
            accExpr = withValue

            if index > 0 {
                let nlInterned = interner.intern("\n")
                let nlExpr = arena.appendExpr(.stringLiteral(nlInterned), type: stringType)
                instructions.append(.constValue(result: nlExpr, value: .stringLiteral(nlInterned)))
                let withNL = arena.appendTemporary(type: stringType)
                instructions.append(.call(callee: concatCallee, arguments: [accExpr, nlExpr], result: withNL, canThrow: false))
                accExpr = withNL
            }
        }

        return accExpr
    }
}
