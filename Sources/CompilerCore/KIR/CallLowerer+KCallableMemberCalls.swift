
/// KProperty / KFunction reflection-aware member-call lowerings.
///
/// Split out from `CallLowerer+MemberCalls.swift`.
extension CallLowerer {
    // MARK: - KProperty member access lowering (PROP-007)

    private func isKCallableReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return false
        }
        let resolvedName = interner.resolve(symbol.name)
        return resolvedName == "KCallable"
            || resolvedName == "KFunction"
            || resolvedName == "KFunction0"
            || resolvedName == "KFunction1"
            || resolvedName == "KFunction2"
            || resolvedName == "KFunction3"
            || resolvedName == "KProperty"
            || resolvedName == "KProperty0"
            || resolvedName == "KProperty1"
            || resolvedName == "KProperty2"
            || resolvedName == "KMutableProperty"
            || resolvedName == "KMutableProperty0"
            || resolvedName == "KMutableProperty1"
            || resolvedName == "KMutableProperty2"
    }

    func tryLowerKPropertyMemberAccess(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let calleeStr = interner.resolve(calleeName)
        guard ["name", "returnType", "parameters", "typeParameters", "visibility", "isFinal", "isOpen", "isAbstract", "isSuspend"].contains(calleeStr) else { return nil }
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        if case .functionType = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
           let property = sema.bindings.identifierSymbol(for: exprID),
           let propertyType = sema.symbols.propertyType(for: property),
           let receiver = Optional(driver.exprLowerer.lowerExpr(
               receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
               propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
           )) {
            return tryLowerInterfaceItablePropertyGetterRead(
                propertySymbol: property, loweredReceiverID: receiver, resultType: propertyType,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
        }
        guard isKCallableReceiverType(receiverType, sema: sema, interner: interner) else { return nil }
        guard let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
              !sema.symbols.isSourceBackedSymbol(propertySymbol)
        else {
            return nil
        }

        // Lower the receiver expression.
        let receiverID = driver.exprLowerer.lowerExpr(
            receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let resultType = sema.bindings.exprTypes[exprID]
            ?? (calleeStr == "name" ? sema.types.stringType : sema.types.anyType)
        let result = arena.appendTemporary(type: resultType)
        emitNonThrowingCall(
            callee: interner.intern(
                calleeStr == "name" ? "__kk_kcallable_get_name" : "__kk_kcallable_get_return_type"
            ),
            arg: receiverID,
            result: result,
            into: &instructions
        )
        return result
    }

    /// Emits a KCallable metadata property after the safe-call null check has
    /// already passed.
    func tryLowerKCallableNameAccess(
        propertySymbol: SymbolID?,
        receiverType: TypeID,
        receiverID: KIRExprID,
        result: KIRExprID,
        calleeName: InternedString,
        sema: SemaModule,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> Bool {
        let memberName = interner.resolve(calleeName)
        guard (memberName == "name" || memberName == "returnType"),
              let propertySymbol,
              !sema.symbols.isSourceBackedSymbol(propertySymbol),
              isKCallableReceiverType(receiverType, sema: sema, interner: interner)
        else {
            return false
        }
        emitNonThrowingCall(
            callee: interner.intern(
                memberName == "name" ? "__kk_kcallable_get_name" : "__kk_kcallable_get_return_type"
            ),
            arg: receiverID,
            result: result,
            into: &instructions
        )
        return true
    }

    // MARK: - KFunction member access lowering (STDLIB-REFLECT-063)

    private func isKFunctionReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        // Check for KFunction class types.
        if let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema)
        {
            let resolvedName = interner.resolve(symbol.name)
            return resolvedName == "KFunction" || resolvedName == "KFunction0"
                || resolvedName == "KFunction1" || resolvedName == "KFunction2"
                || resolvedName == "KFunction3" || resolvedName == "KCallable"
        }
        // Also check function types — callable references (`::foo`) have function types
        // but are tagged as KFunction at runtime.
        if case .functionType = sema.types.kind(of: nonNullType) {
            return false // Plain function types are not KFunction; only tagged callable refs are.
        }
        return false
    }

    /// Known KFunction member names and their corresponding runtime function.
    private static let kFunctionMemberMap: [String: String] = [
        "name": "__kk_kcallable_get_name",
        "returnType": "__kk_kcallable_get_return_type",
        "parameters": "__kk_kfunction_get_parameters",
        "valueParameters": "__kk_kfunction_get_value_parameters",
        "isSuspend": "__kk_kfunction_is_suspend",
        "type": "__kk_kfunction_get_type",
    ]

    func tryLowerKFunctionMemberAccess(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let calleeStr = interner.resolve(calleeName)
        guard let runtimeFunc = Self.kFunctionMemberMap[calleeStr] else { return nil }
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
           sema.symbols.isSourceBackedSymbol(propertySymbol)
        {
            return nil
        }

        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        guard isKFunctionReceiverType(receiverType, sema: sema, interner: interner) else { return nil }

        // Lower the receiver expression.
        let receiverID = driver.exprLowerer.lowerExpr(
            receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let result = arena.appendTemporary(type: resultType
        )
        emitNonThrowingCall(
            callee: interner.intern(runtimeFunc),
            arg: receiverID,
            result: result,
            into: &instructions
        )
        return result
    }

    // MARK: - KParameter member access lowering (STDLIB-REFLECT-TYPE-013)

    private func isKParameterReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return false
        }
        return interner.resolve(symbol.name) == "KParameter"
    }

    /// Known KParameter member names and their corresponding runtime function.
    private static let kParameterMemberMap: [String: String] = [
        "index": "__kk_kparameter_get_index",
        "name": "__kk_kparameter_get_name",
        "type": "__kk_kparameter_get_type",
        "isOptional": "__kk_kparameter_is_optional",
        "kind": "__kk_kparameter_get_kind",
    ]

    func tryLowerKParameterMemberAccess(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let calleeStr = interner.resolve(calleeName)
        guard let runtimeFunc = Self.kParameterMemberMap[calleeStr] else { return nil }

        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        guard isKParameterReceiverType(receiverType, sema: sema, interner: interner) else { return nil }

        let receiverID = driver.exprLowerer.lowerExpr(
            receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let result = arena.appendTemporary(type: resultType
        )
        emitNonThrowingCall(
            callee: interner.intern(runtimeFunc),
            arg: receiverID,
            result: result,
            into: &instructions
        )
        return result
    }

    /// Lowers KFunction.call() with arguments to the appropriate arity-specific runtime call.
    func tryLowerKFunctionCallInvocation(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let calleeStr = interner.resolve(calleeName)
        guard calleeStr == "call" || calleeStr == "callBy" else { return nil }

        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        guard case .functionType = sema.types.kind(of: sema.types.makeNonNullable(receiverType)) else { return nil }

        // Lower the receiver expression (the KFunction handle).
        let receiverID = driver.exprLowerer.lowerExpr(
            receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        if calleeStr == "callBy", let arg = args.first {
            let map = driver.exprLowerer.lowerExpr(arg.expr, ast: ast, sema: sema, arena: arena, interner: interner,
                                                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)
            let result = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(symbol: nil, callee: interner.intern("__kk_kcallable_call_by"), arguments: [receiverID, map],
                                      result: result, canThrow: true, thrownResult: nil))
            let typed = arena.appendTemporary(type: sema.bindings.exprTypes[exprID])
            instructions.append(.copy(from: result, to: typed))
            return typed
        }

        // Lower all arguments.
        var argExprs: [KIRExprID] = []
        for arg in args {
            let argExpr = driver.exprLowerer.lowerExpr(
                arg.expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            argExprs.append(boxValueForAnySlot(
                argExpr, sourceType: sema.bindings.exprTypes[arg.expr] ?? sema.types.anyType, types: sema.types,
                symbols: sema.symbols, interner: interner, arena: arena, requireNonNull: true, into: &instructions
            ))
        }

        let list = driver.callSupportLowerer.packVarargArguments(
            argIndices: Array(argExprs.indices), providedArguments: argExprs, spreadFlags: args.map(\.isSpread),
            boxPrimitiveElements: false, arena: arena, interner: interner,
            intType: sema.types.intType, anyType: sema.types.anyType, types: sema.types, symbols: sema.symbols,
            instructions: &instructions
        )
        let raw = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(symbol: nil, callee: interner.intern("__kk_kcallable_call"), arguments: [receiverID, list],
                                  result: raw, canThrow: true, thrownResult: nil))
        let typed = arena.appendTemporary(type: sema.bindings.exprTypes[exprID])
        instructions.append(.copy(from: raw, to: typed))
        return typed

    }
}
