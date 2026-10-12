extension LambdaLowerer {
    /// `(receiver, args...) -> result` call target for a callable reference
    /// to an interface / open / abstract member function (`t::apply` with
    /// `t: Transformer<Int, Int>`, `Base::foo`).
    ///
    /// The reference's target symbol is the *declaring* member, which for an
    /// interface or abstract method is a body-less stub; calling it directly
    /// yields the stub's zero value instead of the implementer's result. This
    /// returns a thunk that performs the same itable / vtable dispatch a
    /// literal `receiver.member(args)` call would, or `nil` when the call
    /// resolves statically (final receiver type, top-level / extension
    /// function, constructor, suspend or compiler-provided owner).
    func virtualFunctionReferenceThunk(
        targetSymbol: SymbolID,
        receiverStaticType: TypeID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) -> (symbol: SymbolID, name: InternedString)? {
        guard let targetInfo = sema.symbols.symbol(targetSymbol),
              targetInfo.kind == .function,
              let signature = sema.symbols.functionSignature(for: targetSymbol),
              !signature.isSuspend,
              !TypeCheckHelpers().declaresExtensionReceiver(targetSymbol, sema: sema, interner: interner),
              let ownerType = signature.receiverType,
              let owner = sema.symbols.parentSymbol(for: targetSymbol),
              let ownerInfo = sema.symbols.symbol(owner),
              ownerInfo.kind == .class || ownerInfo.kind == .interface,
              !ownerInfo.flags.contains(.synthetic),
              !ownerInfo.flags.contains(.importedLibrary),
              signature.valueParameterSymbols.count == signature.parameterTypes.count
        else {
            return nil
        }
        let dispatchReceiverType = receiverStaticType ?? ownerType
        // Runtime-backed MutableList boxes have no Kotlin itable. Match the
        // direct-call lowering for MutableList.add so a bound reference uses
        // the runtime bridge instead of looking up a missing interface slot.
        let runtimeBackedListCallee: InternedString? = receiverStaticType.flatMap { receiverType in
            guard interner.resolve(targetInfo.name) == "add",
                  signature.parameterTypes.count == 1,
                  signature.returnType == sema.types.booleanType
            else {
                return nil
            }
            return driver.callLowerer.runtimeBackedListMemberCallee(
                memberName: "add",
                receiverType: receiverType,
                chosenCallee: targetSymbol,
                sema: sema,
                interner: interner
            )
        }
        let dispatch = runtimeBackedListCallee == nil
            ? driver.callLowerer.resolveVirtualDispatch(
                callee: targetSymbol,
                receiverTypeID: dispatchReceiverType,
                sema: sema,
                interner: interner
            )
            : nil
        guard runtimeBackedListCallee != nil || dispatch != nil else {
            return nil
        }

        let name = targetInfo.name
        let thunkFQName = [
            interner.intern("kk_function_virtual_thunk_\(targetSymbol.rawValue)_\(dispatchReceiverType.rawValue)"),
            name,
        ]
        if let existing = sema.symbols.lookup(fqName: thunkFQName) {
            return (existing, name)
        }
        let thunkSymbol = sema.symbols.define(
            kind: .function,
            name: name,
            fqName: thunkFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: thunkSymbol)
        var params = [KIRParameter(symbol: receiverSymbol, type: ownerType)]
        var parameterSymbols: [SymbolID] = []
        var argExprs: [KIRExprID] = []
        var body: [KIRInstruction] = [.beginBlock]
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
        body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))
        for (index, type) in signature.parameterTypes.enumerated() {
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: interner.intern("$p\(index)"),
                fqName: thunkFQName + [interner.intern("$p\(index)")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setPropertyType(type, for: paramSymbol)
            parameterSymbols.append(paramSymbol)
            params.append(KIRParameter(symbol: paramSymbol, type: type))
            let argExpr = arena.appendExpr(.symbolRef(paramSymbol), type: type)
            body.append(.constValue(result: argExpr, value: .symbolRef(paramSymbol)))
            argExprs.append(argExpr)
        }
        if let runtimeBackedListCallee {
            let boxedResult = arena.appendTemporary(type: sema.types.anyType)
            let thrownResult = arena.appendTemporary(type: sema.types.nullableAnyType)
            body.append(.constValue(result: thrownResult, value: .null))
            body.append(.call(
                symbol: nil,
                callee: runtimeBackedListCallee,
                arguments: [receiverExpr] + argExprs,
                result: boxedResult,
                canThrow: true,
                thrownResult: thrownResult
            ))
            let rethrowLabel = driver.ctx.makeLoopLabel()
            let continuationLabel = driver.ctx.makeLoopLabel()
            body.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
            let result = arena.appendTemporary(type: signature.returnType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_unbox_bool_static"),
                arguments: [boxedResult],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            body.append(.jump(continuationLabel))
            body.append(.label(rethrowLabel))
            body.append(.rethrow(value: thrownResult))
            body.append(.label(continuationLabel))
            body.append(.returnValue(result))
        } else if let dispatch {
            let result = arena.appendTemporary(type: signature.returnType)
            let probeEndLabel = driver.callLowerer.emitFloatingPointRangeMemberProbe(
                chosenCallee: targetSymbol,
                receiverID: receiverExpr,
                arguments: argExprs,
                result: result,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body
            )
            body.append(.virtualCall(
                symbol: targetSymbol,
                callee: name,
                receiver: receiverExpr,
                arguments: argExprs,
                result: result,
                canThrow: false,
                thrownResult: nil,
                dispatch: dispatch
            ))
            if let probeEndLabel {
                body.append(.label(probeEndLabel))
            }
            switch sema.types.kind(of: signature.returnType) {
            case .unit, .nothing(.nonNull), .nothing(.nullable):
                body.append(.returnUnit)
            default:
                body.append(.returnValue(result))
            }
        }
        body.append(.endBlock)
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: signature.parameterTypes,
                returnType: signature.returnType,
                valueParameterSymbols: parameterSymbols
            ),
            for: thunkSymbol
        )
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: thunkSymbol,
            name: name,
            params: params,
            returnType: signature.returnType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))
        return (thunkSymbol, name)
    }
}
