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
        guard let dispatch = driver.callLowerer.resolveVirtualDispatch(
            callee: targetSymbol,
            receiverTypeID: dispatchReceiverType,
            sema: sema,
            interner: interner
        ) else {
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
