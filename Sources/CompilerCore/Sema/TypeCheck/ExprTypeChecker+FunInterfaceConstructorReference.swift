extension ExprTypeChecker {
    func inferFunInterfaceConstructorCallableReference(
        _ expression: ExprID,
        interfaceSymbol: SymbolID,
        expectedType: TypeID?,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        guard let interface = ctx.cachedSymbol(interfaceSymbol),
              interface.kind == .interface,
              interface.flags.contains(.funInterface)
        else {
            return nil
        }

        let expectedFunctionTypeID: TypeID? = {
            guard let expectedType else { return nil }
            if case .functionType = sema.types.kind(of: expectedType) {
                return expectedType
            }
            guard let functionType = sema.types.nominalFunctionType(for: expectedType) else {
                return nil
            }
            return sema.types.make(.functionType(functionType))
        }()
        if expectedType != nil, expectedFunctionTypeID == nil {
            return nil
        }

        let expectedFunction = expectedFunctionTypeID.flatMap { typeID -> FunctionType? in
            guard case let .functionType(functionType) = sema.types.kind(of: typeID) else { return nil }
            return functionType
        }
        let expectedInterface = expectedFunction.flatMap { function in
            resolveClassType(function.returnType, sema: sema)
        }.flatMap { classType in
            classType.classSymbol == interfaceSymbol ? classType : nil
        }
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: interfaceSymbol)
        let interfaceArgs: [TypeArg]
        if let expectedInterface {
            interfaceArgs = expectedInterface.args
        } else if typeParameters.isEmpty {
            interfaceArgs = []
        } else {
            return nil
        }
        guard interfaceArgs.count == typeParameters.count else {
            return nil
        }

        let interfaceType = sema.types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: interfaceArgs,
            nullability: .nonNull
        )))
        guard let samFunctionType = driver.helpers.samCallableReferenceFunctionType(
            for: interfaceType,
            sema: sema
        ) else {
            return nil
        }
        let samFunctionTypeID = sema.types.make(.functionType(samFunctionType))
        let referenceType = sema.types.make(.functionType(FunctionType(
            params: [samFunctionTypeID],
            returnType: interfaceType,
            isCallableReference: true
        )))
        if let expectedFunctionTypeID,
           !sema.types.isSubtype(referenceType, expectedFunctionTypeID)
        {
            sema.diagnostics.error(
                "KSWIFTK-TYPE-0001",
                "Type constraint could not be satisfied.",
                range: range
            )
            sema.bindings.bindExprType(expression, type: sema.types.errorType)
            return sema.types.errorType
        }

        sema.bindings.bindIdentifier(expression, symbol: interfaceSymbol)
        sema.bindings.bindCallableRefKind(expression, kind: .functionRef)
        sema.bindings.bindSamInterfaceType(expression, type: interfaceType)
        sema.bindings.bindSamUnderlyingFunctionType(expression, type: samFunctionTypeID)
        sema.bindings.bindExprType(expression, type: referenceType)
        return referenceType
    }
}
