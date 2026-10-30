
extension CallLowerer {

    private func isKCallableReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        if case let .functionType(functionType) = sema.types.kind(of: nonNullType) {
            return functionType.isCallableReference
        }
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
        guard ["name", "returnType", "parameters", "typeParameters", "visibility", "isFinal", "isOpen", "isAbstract", "isSuspend", "annotations"].contains(calleeStr) else { return nil }
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

    private func isKFunctionReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        if let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema)
        {
            let resolvedName = interner.resolve(symbol.name)
            return resolvedName == "KFunction" || resolvedName == "KFunction0"
                || resolvedName == "KFunction1" || resolvedName == "KFunction2"
                || resolvedName == "KFunction3" || resolvedName == "KCallable"
        }
        if case let .functionType(functionType) = sema.types.kind(of: nonNullType) {
            return functionType.isCallableReference
        }
        return false
    }

    private static let kFunctionMemberMap: [String: String] = [
        "name": "__kk_kcallable_get_name",
        "returnType": "__kk_kcallable_get_return_type",
        "parameters": "__kk_kfunction_get_parameters",
        "valueParameters": "__kk_kfunction_get_value_parameters",
        "isSuspend": "__kk_kfunction_is_suspend",
        "isInline": "__kk_kfunction_is_inline",
        "isOperator": "__kk_kfunction_is_operator",
        "isInfix": "__kk_kfunction_is_infix",
        "isExternal": "__kk_kfunction_is_external",
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

    private static let kParameterMemberMap: [String: String] = [
        "index": "__kk_kparameter_get_index",
        "name": "__kk_kparameter_get_name",
        "type": "__kk_kparameter_get_type",
        "isOptional": "__kk_kparameter_is_optional",
        "isVararg": "__kk_kparameter_is_vararg",
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

        let receiverID = driver.exprLowerer.lowerExpr(
            receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        if calleeStr == "callBy", let arg = args.first {
            let map = driver.exprLowerer.lowerExpr(arg.expr, ast: ast, sema: sema, arena: arena, interner: interner,
                                                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)
            let result = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(callee: interner.intern("__kk_kcallable_call_by"), arguments: [receiverID, map],
                                      result: result, canThrow: true))
            let typed = arena.appendTemporary(type: sema.bindings.exprTypes[exprID])
            instructions.append(.copy(from: result, to: typed))
            return typed
        }

        var argExprs: [KIRExprID] = []
        for arg in args {
            let argExpr = driver.exprLowerer.lowerExpr(
                arg.expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            argExprs.append(boxValueForAnySlot(
                argExpr, sourceType: sema.bindings.exprTypes[arg.expr] ?? sema.types.anyType, types: sema.types,
                symbols: sema.symbols, interner: interner, arena: arena, requireNonNull: true, sema: sema, into: &instructions
            ))
        }

        let list = driver.callSupportLowerer.packVarargArguments(
            argIndices: Array(argExprs.indices), providedArguments: argExprs, spreadFlags: args.map(\.isSpread),
            boxPrimitiveElements: false, arena: arena, interner: interner,
            intType: sema.types.intType, anyType: sema.types.anyType, types: sema.types, symbols: sema.symbols,
            instructions: &instructions
        )
        let raw = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(callee: interner.intern("__kk_kcallable_call"), arguments: [receiverID, list],
                                  result: raw, canThrow: true))
        let typed = arena.appendTemporary(type: sema.bindings.exprTypes[exprID])
        instructions.append(.copy(from: raw, to: typed))
        return typed

    }

    /// Context parameters are not represented in the erased KProperty1 API.
    /// For a statically known unbound property reference, lower `get` against
    /// the accessor so the invocation site's context values reach its ABI.
    func tryLowerContextualKProperty1GetInvocation(
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
        guard interner.resolve(calleeName) == "get",
              args.count == 1,
              !args[0].isSpread,
              let (_, receiverSymbol) = resolveClassTypeSymbol(
                  sema.types.makeNonNullable(sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType),
                  sema: sema
              ),
              ["KProperty1", "KMutableProperty1"].contains(interner.resolve(receiverSymbol.name)),
              let (propertySymbol, referenceExpr) = staticallyReferencedProperty(
                  from: receiverExpr,
                  ast: ast,
                  sema: sema
              ),
              sema.bindings.callableReferenceBinding(for: referenceExpr)?.boundContextParameterTypes.isEmpty ?? true
        else {
            return nil
        }

        let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
            ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        guard let signature = sema.symbols.functionSignature(for: getterSymbol),
              !signature.contextParameterTypes.isEmpty,
              signature.typeParameterSymbols.isEmpty,
              sema.symbols.memberExtensionOwnerSymbol(for: getterSymbol) == nil,
              sema.symbols.parentSymbol(for: propertySymbol).flatMap({ sema.symbols.symbol($0)?.kind }) != .interface
        else {
            return nil
        }

        let contextArguments = contextArgumentValues(
            for: signature,
            callExprID: exprID,
            callBinding: nil,
            sema: sema,
            arena: arena
        )
        guard contextArguments.count == signature.contextParameterTypes.count else { return nil }

        // Keep receiver evaluation so a property holding the reference still initializes.
        let referenceValue = driver.exprLowerer.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = referenceValue
        let propertyReceiver = driver.exprLowerer.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let result = arena.appendTemporary(type: resultType)
        if let (accessorSymbol, dispatch) = resolvePropertyAccessorVirtualDispatch(
            propertySymbol: propertySymbol,
            accessorKind: .getter,
            sema: sema
        ) {
            instructions.append(.virtualCall(
                symbol: accessorSymbol,
                callee: interner.intern("get"),
                receiver: propertyReceiver,
                arguments: contextArguments,
                result: result,
                canThrow: false,
                dispatch: dispatch
            ))
        } else {
            instructions.append(.call(
                symbol: getterSymbol,
                callee: interner.intern("get"),
                arguments: [propertyReceiver] + contextArguments,
                result: result,
                canThrow: false
            ))
        }
        return result
    }

    private func staticallyReferencedProperty(
        from receiverExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> (symbol: SymbolID, referenceExpr: ExprID)? {
        var visited: Set<SymbolID> = []

        func referenceExpression(from expression: ExprID) -> ExprID? {
            if sema.bindings.callableRefKind(for: expression) == .propertyRef,
               sema.bindings.isUnboundCallableRef(expression)
            {
                return expression
            }
            guard case .nameRef = ast.arena.expr(expression),
                  let valueSymbol = sema.bindings.identifierSymbol(for: expression),
                  visited.insert(valueSymbol).inserted,
                  let valueInfo = sema.symbols.symbol(valueSymbol)
            else {
                return nil
            }

            switch valueInfo.kind {
            case .property:
                for (index, declaration) in ast.arena.decls.enumerated() {
                    let declarationID = DeclID(rawValue: Int32(index))
                    guard sema.bindings.declSymbol(for: declarationID) == valueSymbol,
                          case let .propertyDecl(property) = declaration,
                          !property.isVar,
                          property.getter == nil,
                          property.delegateExpression == nil,
                          let initializer = property.initializer
                    else {
                        continue
                    }
                    return referenceExpression(from: initializer)
                }
            case .local:
                for (index, declaration) in ast.arena.exprs.enumerated() {
                    let declarationID = ExprID(rawValue: Int32(index))
                    guard sema.bindings.identifierSymbol(for: declarationID) == valueSymbol,
                          case let .localDecl(_, isMutable, _, initializer, isDelegated, _, _) = declaration,
                          !isMutable,
                          !isDelegated,
                          let initializer
                    else {
                        continue
                    }
                    return referenceExpression(from: initializer)
                }
            default:
                break
            }
            return nil
        }

        guard let referenceExpr = referenceExpression(from: receiverExpr),
              case let .symbol(propertySymbol)? = sema.bindings.callableTarget(for: referenceExpr),
              sema.symbols.symbol(propertySymbol)?.kind == .property
        else {
            return nil
        }
        return (propertySymbol, referenceExpr)
    }

    func tryLowerKProperty0GetInvocation(
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
        guard interner.resolve(calleeName) == "get", args.isEmpty else { return nil }
        let receiverType = sema.types.makeNonNullable(
            sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        )
        guard let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema),
              ["KProperty0", "KMutableProperty0"].contains(interner.resolve(receiverSymbol.name)),
              let getterSymbol = sema.bindings.callBindings[exprID]?.chosenCallee,
              let interfaceSymbol = sema.symbols.parentSymbol(for: getterSymbol),
              let methodSlot = sema.symbols.nominalLayout(for: interfaceSymbol)?.vtableSlots[getterSymbol]
        else {
            return nil
        }

        let receiver = driver.exprLowerer.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: interfaceSymbol,
            sema: sema,
            interner: interner
        )
        let interfaceTypeIDExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: sema.types.intType)
        instructions.append(.constValue(result: interfaceTypeIDExpr, value: .intLiteral(interfaceTypeID)))
        let methodSlotExpr = arena.appendExpr(.intLiteral(Int64(methodSlot)), type: sema.types.intType)
        instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(Int64(methodSlot))))
        let rawResult = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            callee: interner.intern("__kk_kproperty0_get"),
            arguments: [receiver, interfaceTypeIDExpr, methodSlotExpr],
            result: rawResult,
            canThrow: true
        ))
        let typedResult = arena.appendTemporary(type: sema.bindings.exprTypes[exprID] ?? sema.types.anyType)
        instructions.append(.copy(from: rawResult, to: typedResult))
        return typedResult
    }

    /// `KPropertyN.getDelegate`: delegated-property stubs keep their delegate
    /// in `RuntimeKPropertyStub.delegateRaw` (set beside each getValue/
    /// setValue call), so the runtime helper answers it directly; every other
    /// receiver (`::prop` wrappers) dispatches through the registered itable
    /// method — the same dual behavior `__kk_kproperty0_get` uses for `get`.
    func tryLowerKPropertyGetDelegateInvocation(
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
        guard interner.resolve(calleeName) == "getDelegate",
              args.count <= 2,
              args.allSatisfy({ !$0.isSpread })
        else { return nil }
        let receiverType = sema.types.makeNonNullable(
            sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        )
        guard let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema),
              ["KProperty0", "KMutableProperty0", "KProperty1", "KMutableProperty1",
               "KProperty2", "KMutableProperty2"].contains(interner.resolve(receiverSymbol.name)),
              let getDelegateSymbol = sema.bindings.callBindings[exprID]?.chosenCallee,
              let interfaceSymbol = sema.symbols.parentSymbol(for: getDelegateSymbol),
              let methodSlot = sema.symbols.nominalLayout(for: interfaceSymbol)?.vtableSlots[getDelegateSymbol]
        else {
            return nil
        }

        let receiver = driver.exprLowerer.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: interfaceSymbol,
            sema: sema,
            interner: interner
        )
        let interfaceTypeIDExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: sema.types.intType)
        instructions.append(.constValue(result: interfaceTypeIDExpr, value: .intLiteral(interfaceTypeID)))
        let methodSlotExpr = arena.appendExpr(.intLiteral(Int64(methodSlot)), type: sema.types.intType)
        instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(Int64(methodSlot))))
        // KProperty1/2 take receiver arguments; the erased handles are boxed
        // to Any so the itable impl sees its declared erased-`T` convention.
        var forwardedArgs: [KIRExprID] = []
        for arg in args {
            let lowered = driver.exprLowerer.lowerExpr(
                arg.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            forwardedArgs.append(boxValueForAnySlot(
                lowered,
                sourceType: sema.bindings.exprTypes[arg.expr] ?? sema.types.anyType,
                types: sema.types,
                symbols: sema.symbols,
                interner: interner,
                arena: arena,
                requireNonNull: false,
                sema: sema,
                into: &instructions
            ))
        }
        while forwardedArgs.count < 2 {
            let placeholder = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: placeholder, value: .intLiteral(0)))
            forwardedArgs.append(placeholder)
        }
        let arityExpr = arena.appendExpr(.intLiteral(Int64(args.count)), type: sema.types.intType)
        instructions.append(.constValue(result: arityExpr, value: .intLiteral(Int64(args.count))))
        let rawResult = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            callee: interner.intern("__kk_kproperty_get_delegate"),
            arguments: [receiver, interfaceTypeIDExpr, methodSlotExpr, forwardedArgs[0], forwardedArgs[1], arityExpr],
            result: rawResult,
            canThrow: true
        ))
        let typedResult = arena.appendTemporary(type: sema.bindings.exprTypes[exprID] ?? sema.types.anyType)
        instructions.append(.copy(from: rawResult, to: typedResult))
        return typedResult
    }
}
