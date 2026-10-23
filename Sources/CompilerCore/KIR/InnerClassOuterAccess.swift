/// KIR has no first-class notion of "inner class" beyond the `.innerClass`
/// symbol flag: every inner class reserves a synthetic `$outer` field (the
/// first own field slot, see `HeaderCollection`'s `collectNestedClassOrInterfaceHeader`)
/// that stores the enclosing instance passed at construction time. These
/// free functions read/write that link; every lowering path that needs an
/// enclosing instance (implicit property/function reads and writes,
/// `this@Outer`, and constructing `Outer(...).Inner(...)`/bare `Inner(...)`)
/// goes through `resolveOuterChainValue` so the chain-walking logic exists
/// exactly once.

/// Walks the `$outer` chain starting at `receiver` (an already-lowered KIR
/// value) until it reaches an instance of `target` (or a subtype of it),
/// emitting one `kk_array_get_inbounds` load per `inner class` hop. Returns
/// `nil` when `target` is never reached — `receiver`'s class is neither
/// `target` nor an `inner class` with an outer link to follow — so the
/// caller can fall back to its pre-existing (non-inner-class) behavior.
/// Labeled `this` callers can disable subtype matching because the label
/// identifies a specific enclosing instance, not any subtype.
func resolveOuterChainValue(
    from receiver: KIRExprID,
    to target: SymbolID,
    allowSubtypeMatch: Bool = true,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) -> KIRExprID? {
    func receiverClassSymbol(for symbol: SymbolID) -> SymbolID? {
        guard let info = sema.symbols.symbol(symbol) else { return nil }
        switch info.kind {
        case .class, .interface, .object, .enumClass:
            return symbol
        case .field:
            guard let owner = sema.symbols.parentSymbol(for: symbol),
                  sema.symbols.symbol(owner)?.kind == .enumClass
            else {
                return nil
            }
            return owner
        default:
            return nil
        }
    }

    guard let receiverType = arena.exprType(receiver) else { return nil }
    // `target` is usually a nominal class symbol, but a captured local of
    // an enclosing class is also legal: the class-match checks below then
    // never apply and each `$outer` hop is probed only for capture
    // membership (KUU-2955).
    let targetClassSymbol = receiverClassSymbol(for: target)
    let targetType = targetClassSymbol.map {
        sema.types.make(.classType(ClassType(
            classSymbol: $0, args: [], nullability: .nonNull
        )))
    }
    var currentValue = receiver
    var currentType = sema.types.makeNonNullable(receiverType)
    var hops = 0
    while true {
        guard let (_, currentClassSymbol) = resolveClassTypeSymbol(currentType, sema: sema) else {
            return nil
        }
        if let targetClassSymbol, let targetType {
            // A direct nominal-symbol match, checked before any structural
            // `isSubtype` call: two `classType`s built for the very same
            // nominal class (as `target` and `currentType` are, in the by far
            // most common case where the receiver's own class already is the
            // requested owner) do not reliably compare as mutual subtypes when
            // freshly constructed via `types.make` rather than reusing the
            // exact interned `TypeID` -- this is the fast, always-correct
            // check every ordinary (non-inner-class) property/function access
            // relies on.
            if currentClassSymbol.id == targetClassSymbol {
                return currentValue
            }
            if allowSubtypeMatch, sema.types.isSubtype(currentType, targetType) {
                return currentValue
            }
        }
        if sema.bindings.objectLiteralCaptureSymbols(for: currentClassSymbol.id).contains(target),
           let captureOffset = sema.symbols.nominalLayout(for: currentClassSymbol.id)?.fieldOffsets[target]
        {
            let captureType = sema.bindings.capturedLocalType(for: target) ?? targetType ?? sema.types.anyType
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureOffset)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureOffset))))
            let capturedValue = arena.appendTemporary(type: captureType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [currentValue, offsetExpr],
                result: capturedValue,
                canThrow: false,
                thrownResult: nil
            ))
            return capturedValue
        }
        guard currentClassSymbol.flags.contains(.innerClass),
              let outerFieldSymbol = sema.symbols.outerInstanceFieldSymbol(for: currentClassSymbol.id),
              let outerOffset = sema.symbols.nominalLayout(for: currentClassSymbol.id)?.fieldOffsets[outerFieldSymbol],
              let rawOuterOwnerSymbol = sema.symbols.parentSymbol(for: currentClassSymbol.id),
              let outerOwnerSymbol = receiverClassSymbol(for: rawOuterOwnerSymbol)
        else {
            return nil
        }
        let outerType = sema.types.make(.classType(ClassType(classSymbol: outerOwnerSymbol, args: [], nullability: .nonNull)))
        let offsetExpr = arena.appendExpr(.intLiteral(Int64(outerOffset)), type: sema.types.intType)
        instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(outerOffset))))
        let nextValue = arena.appendTemporary(type: outerType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get_inbounds"),
            arguments: [currentValue, offsetExpr],
            result: nextValue,
            canThrow: false,
            thrownResult: nil
        ))
        currentValue = nextValue
        currentType = outerType
        hops += 1
        // An inner-class nesting chain this deep would already have failed
        // elsewhere; guards against an (impossible, but not worth trusting
        // blindly) parentSymbol cycle turning this into an infinite loop.
        if hops > 64 { return nil }
    }
}

/// Loads the immediate enclosing instance stored in an inner class's `$outer` field.
/// Unlike `resolveOuterChainValue`, this does not treat a superclass relationship as
/// a match: during `super(...)` argument evaluation the subclass instance is not initialized.
func resolveImmediateOuterInstance(
    from receiver: KIRExprID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) -> KIRExprID? {
    guard let receiverType = arena.exprType(receiver),
          let (_, receiverClass) = resolveClassTypeSymbol(receiverType, sema: sema),
          receiverClass.flags.contains(.innerClass),
          let outerFieldSymbol = sema.symbols.outerInstanceFieldSymbol(for: receiverClass.id),
          let outerOffset = sema.symbols.nominalLayout(for: receiverClass.id)?.fieldOffsets[outerFieldSymbol],
          let rawOuterOwnerSymbol = sema.symbols.parentSymbol(for: receiverClass.id),
          let outerOwner = sema.symbols.symbol(rawOuterOwnerSymbol),
          [.class, .interface, .object, .enumClass].contains(outerOwner.kind)
    else {
        return nil
    }

    let outerType = sema.types.make(.classType(ClassType(
        classSymbol: rawOuterOwnerSymbol,
        args: [],
        nullability: .nonNull
    )))
    let offsetExpr = arena.appendExpr(.intLiteral(Int64(outerOffset)), type: sema.types.intType)
    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(outerOffset))))
    let outerValue = arena.appendTemporary(type: outerType)
    instructions.append(.call(
        symbol: nil,
        callee: interner.intern("kk_array_get_inbounds"),
        arguments: [receiver, offsetExpr],
        result: outerValue,
        canThrow: false,
        thrownResult: nil
    ))
    return outerValue
}

/// Allocates a fresh heap object for the class `chosen` (a resolved
/// constructor symbol) constructs via `kk_object_new`, and performs every
/// registration a constructor call needs before its `<init>` body runs.
/// When the constructed class is an `inner class`, the `$outer`
/// enclosing-instance link is resolved from `outerReceiver` (the
/// lowered explicit receiver for `outer.Inner(...)`, or the active implicit
/// receiver for a bare `Inner(...)` call from within `Outer`) and stored.
/// Returns the allocated object's KIR value, ready to prepend as the
/// constructor's own `this` argument.
func allocateAndRegisterConstructedObject(
    chosen: SymbolID,
    boundType: TypeID?,
    outerReceiver: KIRExprID?,
    driver: KIRLoweringDriver,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) -> KIRExprID {
    let allocType = boundType ?? sema.types.anyType
    let intType = sema.types.make(.primitive(.int, .nonNull))
    var slotCount: Int64 = 1
    var ownerNominalSymbol: SymbolID?
    if let parentClassID = sema.symbols.parentSymbol(for: chosen),
       let layout = sema.symbols.nominalLayout(for: parentClassID)
    {
        ownerNominalSymbol = parentClassID
        slotCount = Int64(max(layout.instanceSizeWords, 1))
    }
    let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
    instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
    let classIDValue: Int64 = if let ownerNominalSymbol {
        RuntimeTypeCheckToken.stableNominalTypeID(symbol: ownerNominalSymbol, sema: sema, interner: interner)
    } else {
        0
    }
    let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
    let allocatedObj = arena.appendTemporary(type: allocType)
    instructions.append(.call(
        symbol: nil,
        callee: interner.intern("kk_object_new"),
        arguments: [slotCountExpr, classIDExpr],
        result: allocatedObj,
        canThrow: false,
        thrownResult: nil
    ))
    guard let ownerNominalSymbol else { return allocatedObj }
    if sema.symbols.symbol(ownerNominalSymbol)?.flags.contains(.dataType) == true {
        let registerDataClassResult = arena.appendTemporary(type: intType)
        emitNonThrowingCall(
            callee: interner.intern("kk_runtime_register_data_class"),
            arg: classIDExpr,
            result: registerDataClassResult,
            into: &instructions
        )
        if let fieldMask = driver.callLowerer.dataClassFieldSlotMask(owner: ownerNominalSymbol, sema: sema) {
            let maskExpr = arena.appendExpr(.intLiteral(fieldMask), type: intType)
            instructions.append(.constValue(result: maskExpr, value: .intLiteral(fieldMask)))
            let registerFieldsResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_runtime_register_data_class_fields"),
                arguments: [classIDExpr, maskExpr],
                result: registerFieldsResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }
    let childTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
        symbol: ownerNominalSymbol,
        sema: sema,
        interner: interner
    )
    appendNominalSupertypeEdgeRegistrations(
        childSymbol: ownerNominalSymbol,
        sema: sema,
        arena: arena,
        interner: interner,
        instructions: &instructions
    )
    appendObjectItableMethodRegistrations(
        objectValue: allocatedObj,
        nominalSymbol: ownerNominalSymbol,
        driver: driver,
        sema: sema,
        arena: arena,
        interner: interner,
        instructions: &instructions
    )
    appendObjectItablePropertyGetterRegistrations(
        objectValue: allocatedObj,
        nominalSymbol: ownerNominalSymbol,
        sema: sema,
        cache: driver.ctx.nominalDispatchCache,
        arena: arena,
        interner: interner,
        instructions: &instructions
    )
    appendObjectItablePropertySetterRegistrations(
        objectValue: allocatedObj,
        nominalSymbol: ownerNominalSymbol,
        sema: sema,
        cache: driver.ctx.nominalDispatchCache,
        arena: arena,
        interner: interner,
        instructions: &instructions
    )
    appendObjectVtableMethodRegistrations(
        objectValue: allocatedObj,
        nominalSymbol: ownerNominalSymbol,
        driver: driver,
        sema: sema,
        arena: arena,
        interner: interner,
        instructions: &instructions
    )
    appendObjectAnyToStringRegistration(
        objectValue: allocatedObj,
        nominalSymbol: ownerNominalSymbol,
        driver: driver,
        sema: sema,
        arena: arena,
        interner: interner,
        instructions: &instructions
    )
    driver.callLowerer.emitKClassMetadataRegistration(
        objectSymbol: ownerNominalSymbol,
        typeID: childTypeID,
        sema: sema,
        arena: arena,
        interner: interner,
        instructions: &instructions
    )
    if let throwableSymbol = sema.symbols.lookup(
        fqName: [interner.intern("kotlin"), interner.intern("Throwable")]
    ) {
        let ownerType = sema.types.make(.classType(ClassType(
            classSymbol: ownerNominalSymbol,
            args: [],
            nullability: .nonNull
        )))
        let throwableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
        // Capture a Kotlin-defined Throwable subclass at allocation time,
        // before its constructor body can observe the receiver.
        if sema.types.isSubtype(ownerType, throwableType) {
            let captureResult = arena.appendTemporary(type: intType)
            emitNonThrowingCall(
                callee: interner.intern("__kk_throwable_captureStackTrace"),
                arg: allocatedObj,
                result: captureResult,
                into: &instructions
            )
        }
    }
    // KUU-555: a local class's `<init>` runs as an independent KIR
    // function — materialize captured outer locals into the fresh
    // instance's fields here, where the enclosing scope's locals are
    // still active (same convention as object-literal capture
    // materialization in `lowerStoredObjectLiteralExpr`).
    if let layout = sema.symbols.nominalLayout(for: ownerNominalSymbol) {
        for capturedSymbol in sema.bindings.objectLiteralCaptureSymbols(for: ownerNominalSymbol) {
            guard let fieldOffset = layout.fieldOffsets[capturedSymbol],
                  let captureValue = driver.lambdaLowerer.captureValueExpr(
                      for: capturedSymbol,
                      sema: sema,
                      arena: arena,
                      interner: interner,
                      instructions: &instructions
                  )
            else {
                continue
            }
            let captureOffsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
            instructions.append(.constValue(
                result: captureOffsetExpr,
                value: .intLiteral(Int64(fieldOffset))
            ))
            let captureSetResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [allocatedObj, captureOffsetExpr, captureValue],
                result: captureSetResult,
                canThrow: true,
                thrownResult: nil
            ))
        }
    }
    if sema.symbols.symbol(ownerNominalSymbol)?.flags.contains(.innerClass) == true {
        storeOuterInstanceLinkIfNeeded(
            allocatedObject: allocatedObj,
            innerClassSymbol: ownerNominalSymbol,
            outerReceiver: outerReceiver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }
    return allocatedObj
}

/// A no-op when `innerClassSymbol` isn't actually an `inner class`, or when
/// no outer value could be resolved (should not happen for code Sema
/// accepted).
func storeOuterInstanceLinkIfNeeded(
    allocatedObject: KIRExprID,
    innerClassSymbol: SymbolID,
    outerReceiver: KIRExprID?,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) {
    guard let outerFieldSymbol = sema.symbols.outerInstanceFieldSymbol(for: innerClassSymbol),
          let outerOffset = sema.symbols.nominalLayout(for: innerClassSymbol)?.fieldOffsets[outerFieldSymbol],
          let declaredOuterSymbol = sema.symbols.parentSymbol(for: innerClassSymbol),
          let outerReceiver,
          let outerValue = resolveOuterChainValue(
              from: outerReceiver,
              to: declaredOuterSymbol,
              sema: sema,
              arena: arena,
              interner: interner,
              instructions: &instructions
          )
    else {
        return
    }
    let offsetExpr = arena.appendExpr(.intLiteral(Int64(outerOffset)), type: sema.types.intType)
    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(outerOffset))))
    let storeResult = arena.appendTemporary(type: sema.types.anyType)
    instructions.append(.call(
        symbol: nil,
        callee: interner.intern("kk_array_set"),
        arguments: [allocatedObject, offsetExpr, outerValue],
        result: storeResult,
        canThrow: true,
        thrownResult: nil
    ))
}

extension CallLowerer {
    /// Lowers `outer.Inner(args)`. Allocates a genuine new `Inner`
    /// object (via `allocateAndRegisterConstructedObject`, which also
    /// stores the resolved `outer` value into the new object's `$outer`
    /// field) instead of treating the lowered receiver as if it already
    /// were the constructor's own `this` -- seeded by
    /// `lowerMemberLikeCallExpr`'s early intercept, since every generic
    /// member-call special case below it assumes a resolved `chosenCallee`
    /// is an ordinary member function.
    func lowerInnerClassConstructorMemberCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        chosenCtor: SymbolID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let loweredReceiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let allocatedObj = allocateAndRegisterConstructedObject(
            chosen: chosenCtor,
            boundType: boundType,
            outerReceiver: loweredReceiverID,
            driver: driver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let loweredArgIDs = args.map { argument in
            driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let normalized = driver.callSupportLowerer.normalizedCallArguments(
            providedArguments: loweredArgIDs,
            callBinding: sema.bindings.callBindings[exprID],
            chosenCallee: chosenCtor,
            spreadFlags: args.map(\.isSpread),
            argumentLabels: args.map(\.label),
            sourceArgExprs: args.map(\.expr),
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        var finalArguments = normalized.arguments
        finalArguments.insert(allocatedObj, at: 0)
        // Constructors store function arguments just like ordinary source-backed
        // calls. Preserve receiver-lambda captures before default-stub dispatch.
        materializeSourceBackedFunctionValueArguments(
            chosenCallee: chosenCtor,
            sourceArgExprs: args.map(\.expr),
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions,
            arguments: &finalArguments
        )
        appendReifiedTypeTokens(
            chosenCallee: chosenCtor,
            callBinding: sema.bindings.callBindings[exprID],
            sema: sema,
            interner: interner,
            arena: arena,
            instructions: &instructions,
            arguments: &finalArguments
        )
        let result = arena.appendTemporary(type: boundType)
        let calleeName = sema.symbols.symbol(chosenCtor)?.name ?? interner.intern("<init>")
        let stubOwner = driver.callSupportLowerer.defaultStubOwnerSymbol(for: chosenCtor, sema: sema)
        if normalized.hasOmittedDefaultArguments,
           sema.symbols.externalLinkName(for: chosenCtor)?.isEmpty ?? true ||
            sema.symbols.externalLinkName(for: driver.callSupportLowerer.defaultStubSymbol(for: stubOwner)) != nil
        {
            appendDefaultMaskArguments(
                normalized.defaultMaskWords,
                sema: sema,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArguments
            )
            instructions.append(.call(
                symbol: driver.callSupportLowerer.defaultStubSymbol(for: stubOwner),
                callee: interner.intern(interner.resolve(calleeName) + "$default"),
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        instructions.append(.call(
            symbol: chosenCtor,
            callee: calleeName,
            arguments: finalArguments,
            result: result,
            canThrow: true,
            thrownResult: nil
        ))
        return result
    }
}
