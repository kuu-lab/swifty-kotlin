extension LambdaLowerer {
    func lowerFunInterfaceConstructorCallableReference(
        _ expression: ExprID,
        memberName: InternedString,
        interfaceSymbol: SymbolID,
        interfaceType: TypeID,
        samFunctionType: FunctionType,
        boundType: TypeID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let boundType,
              case let .functionType(callableFunctionType) = sema.types.kind(of: boundType),
              callableFunctionType.params.count == 1,
              let interface = sema.symbols.symbol(interfaceSymbol),
              interface.kind == .interface,
              interface.flags.contains(.funInterface),
              case let .classType(classType) = sema.types.kind(of: interfaceType),
              classType.classSymbol == interfaceSymbol
        else {
            return nil
        }

        let callableSymbol = driver.ctx.syntheticLambdaSymbol(for: expression)
        let callableName = syntheticLambdaName(for: expression, interner: interner)
        let closureParam = sema.bindings.isCollectionHOFLambdaExpr(expression)
            ? KIRParameter(symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: expression), type: sema.types.intType)
            : nil
        let valueParam = KIRParameter(
            symbol: syntheticLambdaParamSymbol(lambdaExprID: expression, paramIndex: 0),
            type: callableFunctionType.params[0]
        )

        var body: [KIRInstruction] = [.beginBlock]
        let value = arena.appendExpr(.symbolRef(valueParam.symbol), type: valueParam.type)
        body.append(.constValue(result: value, value: .symbolRef(valueParam.symbol)))
        guard let samValue = lowerFunctionValueSamWrapper(
            expression,
            value: value,
            functionType: samFunctionType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body
        ) else {
            return nil
        }
        body.append(.returnValue(samValue))
        body.append(.endBlock)

        let declaration = arena.appendDecl(.function(KIRFunction(
            symbol: callableSymbol,
            name: callableName,
            params: (closureParam.map { [$0] } ?? []) + [valueParam],
            returnType: callableFunctionType.returnType,
            body: body,
            isSuspend: callableFunctionType.isSuspend,
            isInline: false
        )))
        driver.ctx.appendGeneratedCallableDecl(declaration)

        let callableExpr = arena.appendExpr(.symbolRef(callableSymbol), type: boundType)
        instructions.append(.constValue(result: callableExpr, value: .symbolRef(callableSymbol)))
        let isCollectionHOFReference = sema.bindings.isCollectionHOFLambdaExpr(expression)
        driver.ctx.registerCallableValue(
            callableExpr,
            symbol: callableSymbol,
            callee: callableName,
            captureArguments: [],
            hasClosureParam: isCollectionHOFReference
        )
        if isCollectionHOFReference {
            emitFunctionValueTypeTag(
                callableExpr,
                functionType: callableFunctionType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return callableExpr
        }

        let taggedExpr = emitCallableRefTypeTag(
            callableExpr: callableExpr,
            callableType: boundType,
            refKind: .functionRef,
            memberName: memberName,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        // The generated adapter function is unique per reference expression,
        // but Kotlin compares references to the same SAM constructor by target.
        emitCallableReferenceIdentity(
            callableExpr: taggedExpr,
            targetSymbol: interfaceSymbol,
            identityTargetRaw: RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: interfaceSymbol,
                sema: sema,
                interner: interner
            ),
            captures: [],
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        registerCallableReflection(
            value: taggedExpr,
            callableSymbol: callableSymbol,
            callableName: callableName,
            targetSymbol: nil,
            parameterTypes: callableFunctionType.params,
            returnType: callableFunctionType.returnType,
            captures: [],
            receiverCount: 0,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        driver.ctx.registerCallableValue(
            taggedExpr,
            symbol: callableSymbol,
            callee: callableName,
            captureArguments: []
        )
        return taggedExpr
    }
}
