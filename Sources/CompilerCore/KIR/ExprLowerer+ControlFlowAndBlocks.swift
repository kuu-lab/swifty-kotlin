Warning: truncated output (original token count: 42774)
Total output lines: 3294

// swiftlint:disable file_length

extension ExprLowerer {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func lowerExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        guard let expr = ast.arena.expr(exprID) else {
            let temp = arena.appendTemporary(type: sema.types.errorType)
            instructions.append(.constValue(result: temp, value: .unit))
            return temp
        }
        let stringType = sema.types.stringType

        switch expr {
        case let .intLiteral(value, _):
            let id = arena.appendExpr(.intLiteral(value), type: boundType ?? intType)
            instructions.append(.constValue(result: id, value: .intLiteral(value)))
            return id

        case let .longLiteral(value, _):
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let id = arena.appendExpr(.longLiteral(value), type: boundType ?? longType)
            instructions.append(.constValue(result: id, value: .longLiteral(value)))
            return id

        case let .uintLiteral(value, _):
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let id = arena.appendExpr(.uintLiteral(value), type: boundType ?? uintType)
            instructions.append(.constValue(result: id, value: .uintLiteral(value)))
            return id

        case let .ulongLiteral(value, _):
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let id = arena.appendExpr(.ulongLiteral(value), type: boundType ?? ulongType)
            instructions.append(.constValue(result: id, value: .ulongLiteral(value)))
            return id

        case let .floatLiteral(value, _):
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let id = arena.appendExpr(.floatLiteral(value), type: boundType ?? floatType)
            instructions.append(.constValue(result: id, value: .floatLiteral(value)))
            return id

        case let .doubleLiteral(value, _):
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let id = arena.appendExpr(.doubleLiteral(value), type: boundType ?? doubleType)
            instructions.append(.constValue(result: id, value: .doubleLiteral(value)))
            return id

        case let .charLiteral(value, _):
            let charType = sema.types.make(.primitive(.char, .nonNull))
            let id = arena.appendExpr(.charLiteral(value), type: boundType ?? charType)
            instructions.append(.constValue(result: id, value: .charLiteral(value)))
            return id

        case let .boolLiteral(value, _):
            let id = arena.appendExpr(.boolLiteral(value), type: boundType ?? boolType)
            instructions.append(.constValue(result: id, value: .boolLiteral(value)))
            return id

        case let .stringLiteral(value, _):
            let id = arena.appendExpr(.stringLiteral(value), type: boundType ?? stringType)
            instructions.append(.constValue(result: id, value: .stringLiteral(value)))
            return id

        case let .stringTemplate(parts, _):
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

        case let .nameRef(name, _):
            let nullID = interner.intern("null")
            let thisID = interner.intern("this")
            // Resolve lambda param by name (handles collection HOF fallback where identifierSymbols may be unbound).
            if let paramSymbol = driver.ctx.lambdaParamSymbol(named: name),
               let localValue = driver.ctx.localValue(for: paramSymbol)
            {
                return localValue
            }
            if name == nullID {
                let id = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
                instructions.append(.constValue(result: id, value: .null))
                return id
            }
            if name == thisID,
               let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
            {
                return receiverExprID
            }
            // BUG-B/BUG-C: an enum value has no stored-field object layout
            // (its KIR representation is a raw ordinal Int, only boxed for
            // Any-erased contexts), so an implicit-receiver read of its
            // built-in `name`/`ordinal` properties or of a constructor
            // property falls through every `.class`/`.interface`-owner
            // branch below and lands on the generic symbol-reference
            // fallback near the end of this case -- silently wrong (reads an
            // unwritten slot as 0) for an Int-typed property, and a SIGSEGV
            // once codegen treats the bogus "pointer" as a String for a
            // String-typed one. Mirror the explicit-receiver handling
            // (`tryLowerEnumEntryPropertyRead` / the enum branch of
            // `lowerStoredMemberPropertyReadValue` in
            // CallLowerer+MemberPropertyReads.swift) here, before any of
            // those generic branches can intercept the read.
            if let symbol = sema.bindings.identifierSymbols[exprID]
                ?? sema.bindings.callBindings[exprID]?.chosenCallee,
               let symInfo = sema.symbols.symbol(symbol),
               symInfo.kind == .property,
               symInfo.name == interner.intern("name") || symInfo.name == interner.intern("ordinal"),
               let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
               let receiverType = arena.exprType(receiverExprID),
               let (_, receiverClassSym) = resolveClassTypeSymbol(
                   sema.types.makeNonNullable(receiverType), sema: sema
               ),
               receiverClassSym.kind == .enumClass
            {
                let resultType = boundType ?? sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                if symInfo.name == interner.intern("ordinal") {
                    return emitNonThrowingCall(
                        callee: ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner),
                        arg: receiverExprID,
                        resultType: resultType,
                        arena: arena,
                        into: &instructions
                    )
                }
                let result = arena.appendTemporary(type: resultType)
                instructions.append(.call(
                    symbol: nil,
                    callee: symInfo.name,
                    arguments: [receiverExprID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if let symbol = sema.bindings.identifierSymbols[exprID]
                ?? sema.bindings.callBindings[exprID]?.chosenCallee,
               let symInfo = sema.symbols.symbol(symbol),
               // `.field` is deliberately excluded: a bare reference to an
               // enum *entry* itself (e.g. `NORTH` inside the companion
               // object's `when (direction) { NORTH -> SOUTH; ... }`) also
               // resolves to a `.field` symbol parented by the enum class,
               // but it names a global entry constant, not an instance
               // property -- routing it through the constructor-property
               // placeholder below produced an unresolved
               // `$enumConstructorProperty$<id>$NORTH` call.
               symInfo.kind == .property,
               let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
               sema.symbols.symbol(ownerSymbol)?.kind == .enumClass,
               let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
            {
                let resultType = boundType ?? sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                let result = arena.appendTemporary(type: resultType)
                if driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema) {
                    let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                    instructions.append(.call(
                        symbol: getterSymbol,
                        callee: interner.intern("get"),
                        arguments: [receiverExprID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let helperName = interner.intern(
                    "$enumConstructorProperty$\(ownerSymbol.rawValue)$\(interner.resolve(symInfo.name))"
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: helperName,
                    arguments: [receiverExprID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // STDLIB-004: Implicit receiver member access (e.g. `length` inside
            // `run { length }` resolves as `this.length`).
            if let memberName = sema.bindings.implicitReceiverMemberNames[exprID],
               let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
            {
                // KSP-CAP-001: an enclosing immutable property captured by an
                // object-literal member function is restored as a local value.
                // It must take precedence over the implicit receiver member
                // path, which would otherwise apply the enclosing property's
                // field offset to the object literal receiver.
                if let symbol = sema.bindings.identifierSymbols[exprID],
                   sema.symbols.symbol(symbol)?.kind == .property,
                   !driver.ctx.isMutableCaptureBoxed(symbol),
                   let localValue = driver.ctx.localValue(for: symbol)
                {
                    return localValue
                }
                let receiverType = arena.exprType(receiverExprID) ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                let memberStr = interner.resolve(memberName)
                let resultType = boundType ?? sema.types.anyType
                let result = arena.appendTemporary(type: resultType
                )
                // Enum entry body functions use the enum value itself as
                // their implicit receiver. Its runtime representation is the
                // entry ordinal, so the synthetic Enum.name property cannot
                // be read as an ordinary stored property on that receiver.
                // Route it through the same enum-name rewrite used for
                // explicit receiver reads; ordinal is already the boxed
                // receiver's integer payload.
                if (memberStr == "name" || memberStr == "ordinal"),
                   let (_, receiverClass) = resolveClassTypeSymbol(
                       nonNullReceiverType,
                       sema: sema
                   ),
                   receiverClass.kind == .enumClass
                {
                    if memberStr == "ordinal" {
                        emitNonThrowingCall(
                            callee: interner.intern("kk_unbox_int"),
                            arg: receiverExprID,
                            result: result,
                            into: &instructions
                        )
                    } else {
                        instructions.append(.call(
                            symbol: nil,
                            callee: memberName,
                            arguments: [receiverExprID],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    }
                    return result
                }
                // String properties
                if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                    if memberStr == "length" {
                        emitNonThrowingCall(
                            callee: interner.intern("__kk_string_struct_get_length"),
                            arg: receiverExprID,
                            result: result,
                            into: &instructions
                        )
                        return result
                    }
                }

                // Collection properties: size, isEmpty. Restricted to receivers
                // that are collections (or of unknown class), so that a user
                // class declaring its own `size`/`isEmpty` member keeps its
                // declared accessor / backing field on implicit-receiver reads.
                let receiverMayBeCollection = resolveClassTypeSymbol(nonNullReceiverType, sema: sema)
                    .map { KnownCompilerNames(interner: interner).isCollectionLikeSymbol($0.symbol) }
                    ?? true
                // Abstract class properties have no usable declaration-local
                // field value. Resolve them through the class vtable before
                // collection shortcuts or the stored-field fallback below.
                if let propertySymbol = sema.bindings.identifierSymbols[exprID],
                   let (accessorSymbol, dispatch) = driver.callLowerer.tryResolvePropertyAccessorVirtualDispatch(
                       propertySymbol: propertySymbol,
                       receiverExpr: exprID,
                       accessorKind: .getter,
                       ast: ast,
                       sema: sema,
                       interner: interner
                   )
                {
                    instructions.append(.virtualCall(
                        symbol: accessorSymbol,
                        callee: interner.intern("get"),
                        receiver: receiverExprID,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil,
                        dispatch: dispatch
                    ))
                    return result
                }

                // A user-declared member with a custom getter shadows the built-in
                // collection shortcuts below: `size` / `isEmpty` inside a class that
                // declares them must run its own getter, not kk_collection_size.
                let implicitMemberUsesAccessor: Bool = {
                    guard let symbol = sema.bindings.identifierSymbols[exprID],
                          let sym = sema.symbols.symbol(symbol),
                          sym.kind == .property,
                          let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                          let ownerKind = sema.symbols.symbol(ownerSymbol)?.kind,
                          ownerKind == .class || ownerKind == .interface
                    else {
                        return false
                    }
                    return driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema)
                }()

                if receiverMayBeCollection, memberStr == "size", !implicitMemberUsesAccessor {
                    emitNonThrowingCall(
                        callee: interner.intern("__kk_collection_size"),
                        arg: receiverExprID,
                        result: result,
                        into: &instructions
                    )
                    return result
                }
                if receiverMayBeCollection, memberStr == "isEmpty", !implicitMemberUsesAccessor {
                    emitNonThrowingCall(
                        callee: interner.intern("__kk_collection_isEmpty"),
                        arg: receiverExprID,
                        result: result,
                        into: &instructions
                    )
                    return result
                }

                // Some implicit member expressions carry their selected
                // property only in the call binding. Preserve the same
                // abstract/open class dispatch in that representation too.
                if let symbol = sema.bindings.identifierSymbols[exprID]
                    ?? sema.bindings.callBindings[exprID]?.chosenCallee,
                   let propertyInfo = sema.symbols.symbol(symbol),
                   propertyInfo.kind == .property,
                   propertyInfo.flags.contains(.abstractType)
                       || propertyInfo.flags.contains(.openType),
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let ownerInfo = sema.symbols.symbol(ownerSymbol),
                   ownerInfo.kind == .class,
                   !sema.symbols.directSubtypes(of: ownerSymbol).isEmpty,
                   let getterSlot = sema.symbols.nominalLayout(for: ownerSymbol)?.vtableSlots[
                       SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                   ]
                {
                    let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                    instructions.append(.virtualCall(
                        symbol: getterSymbol,
                        callee: interner.intern("get"),
                        receiver: receiverExprID,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil,
                        dispatch: .vtable(slot: getterSlot)
                    ))
                    return result
                }

                // KSP-CAP-018: a computed object-literal property has no
                // instance field anyone writes, so reading it through the
                // implicit receiver has to call its `get` accessor — this path
                // used to fall straight through to the field load below and
                // return the zeroed slot. The explicit-receiver read
                // (`tryLowerObjectLiteralStoredPropertyRead`) already did this;
                // both now share one predicate so they cannot disagree about
                // whether an accessor exists to call.
                if let symbol = sema.bindings.identifierSymbols[exprID],
                   sema.bindings.isObjectLiteralPropertySymbol(symbol),
                   driver.callLowerer.objectLiteralPropertyUsesAccessor(symbol, ast: ast, sema: sema)
                {
                    instructions.append(.call(
                        symbol: symbol,
                        callee: interner.intern("get"),
                        arguments: [receiverExprID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }

                if let symbol = sema.bindings.identifierSymbols[exprID],
                   sema.bindings.isObjectLiteralPropertySymbol(symbol),
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[symbol]
                {
                    let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [receiverExprID, offsetExpr],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return wrapLateinitReadIfNeeded(
                        result,
                        symbol: symbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                }

                // Native stub properties with externalLinkName: call native function
                // directly via the implicit receiver (e.g. kk_duration_inWholeNanoseconds
                // accessed inside a bundled Kotlin source extension getter body).
                if let symbol = sema.bindings.identifierSymbols[exprID],
                   let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property,
                   let externalLinkName = sema.symbols.externalLinkName(for: symbol),
                   !externalLinkName.isEmpty
                {
                    instructions.append(.call(
                        symbol: symbol,
                        callee: interner.intern(externalLinkName),
                        arguments: [receiverExprID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }

                if let symbol = sema.bindings.identifierSymbols[exprID],
                   let interfaceRead = driver.callLowerer.tryLowerInterfaceItablePropertyGetterRead(
                       propertySymbol: symbol,
                       loweredReceiverID: receiverExprID,
                       resultType: resultType,
                       sema: sema,
                       arena: arena,
                       interner: interner,
                       instructions: &instructions
                   )
                {
                    return interfaceRead
                }

                // KSP-928: implicit reads of abstract/open class properties
                // must dispatch through the class vtable. This is the path
                // used by AbstractMap's skeletal methods for `entries`.
                if let symbol = sema.bindings.identifierSymbols[exprID],
                   let propertyInfo = sema.symbols.symbol(symbol),
                   propertyInfo.kind == .property,
                   propertyInfo.flags.contains(.abstractType)
                       || propertyInfo.flags.contains(.openType),
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let ownerInfo = sema.symbols.symbol(ownerSymbol),
                   ownerInfo.kind == .class,
                   !sema.symbols.directSubtypes(of: ownerSymbol).isEmpty,
                   let getterSlot = sema.symbols.nominalLayout(for: ownerSymbol)?.vtableSlots[
                       SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                   ]
                {
                    let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                    instructions.append(.virtualCall(
                        symbol: getterSymbol,
                        callee: interner.intern("get"),
                        receiver: receiverExprID,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil,
                        dispatch: .vtable(slot: getterSlot)
                    ))
                    return result
                }

                // A custom getter must run for implicit-receiver reads just as
                // it does for an explicit `receiver.property` read.
                if let symbol = sema.bindings.identifierSymbols[exprID],
                   let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property,
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let ownerKind = sema.symbols.symbol(ownerSymbol)?.kind,
                   ownerKind == .class || ownerKind == .interface,
                   driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema)
                {
                    let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                    instructions.append(.call(
                        symbol: getterSymbol,
                        callee: interner.intern("get"),
                        arguments: [receiverExprID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }

                if let symbol = sema.bindings.identifierSymbols[exprID],
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let ownerInfo = sema.symbols.symbol(ownerSymbol),
                   ownerInfo.kind == .class || ownerInfo.kind == .interface,
                   let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                       sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
                   ]
                {
                    let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [receiverExprID, offsetExpr],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return wrapLateinitReadIfNeeded(
                        result,
                        symbol: symbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                }

                // General fallback: try to find a getter symbol for the property
                if let symbol = sema.bindings.identifierSymbols[exprID],
                   !driver.ctx.isMutableCaptureBoxed(symbol)
                {
                    if let delegateValue = readLocalDelegateValue(
                        symbol: symbol, sema: sema, arena: arena, interner: interner,
                        instructions: &instructions
                    ) {
                        return delegateValue
                    }
                    if let localValue = driver.ctx.localValue(for: symbol) {
                        return localValue
                    }
                }
            }
            if let boundIdentifierSymbol = sema.bindings.identifierSymbols[exprID] {
                // A bare `ClassName` value expression (not `ClassName.member()`,
                // which resolves through ordinary member lookup) that names a
                // class/interface/enum with a companion object is, per Kotlin's
                // own semantics, a reference to that companion object's
                // singleton instance -- the class symbol itself carries no
                // runtime value. Sema types this expression as the class's
                // nominal type (see ExprTypeChecker+NameLambdaAndCallableRefInference
                // .resolveTypeForCandidate) precisely so `ClassName.member()`
                // keeps resolving, but `identifierSymbols` still names the
                // class; redirect to the companion here so the branches below
                // (which key off `symbol.kind`) see the object, not the class.
                let symbol: SymbolID = {
                    if let symInfo = sema.symbols.symbol(boundIdentifierSymbol),
                       symInfo.kind == .class || symInfo.kind == .interface || symInfo.kind == .enumClass,
                       let companionSymbol = sema.symbols.companionObjectSymbol(for: boundIdentifierSymbol)
                    {
                        return companionSymbol
                    }
                    return boundIdentifierSymbol
                }()
                if driver.ctx.isMutableCaptureBoxed(symbol),
                   let loadedValue = loadMutableCaptureCellValue(
                       symbol: symbol,
                       resultType: {
                           driver.ctx.localDeclaredType(for: symbol)
                               ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                       }(),
                       sema: sema,
                       arena: arena,
                       interner: interner,
                       instructions: &instructions
                   )
                {
                    return loadedValue
                }
                if let delegateValue = readLocalDelegateValue(
                    symbol: symbol, sema: sema, arena: arena, interner: interner,
                    instructions: &instructions
                ) {
                    return delegateValue
                }
                if let localValue = driver.ctx.localValue(for: symbol) {
                    return localValue
                }
                // A bare companion/object property reference can resolve
                // directly to the property symbol without being marked as an
                // implicit-receiver member. Computed object properties still
                // have a one-parameter getter ABI, so materialize the singleton
                // receiver instead of leaving PropertyLoweringPass to emit a
                // zero-argument getter call.
                if let symInfo = sema.symbols.symbol(symbol),
                   symInfo.kind == .property,
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   sema.symbols.symbol(ownerSymbol)?.kind == .object,
                   sema.symbols.propertyHasCustomGetter(for: symbol)
                       || sema.symbols.extensionPropertyGetterAccessor(for: symbol) != nil
                {
                    let ownerType = sema.types.make(.classType(ClassType(
                        classSymbol: ownerSymbol,
                        args: [],
                        nullability: .nonNull
                    )))
                    let receiver = arena.appendExpr(.symbolRef(ownerSymbol), type: ownerType)
                    instructions.append(.constValue(result: receiver, value: .symbolRef(ownerSymbol)))
                    let resultType = boundType
                        ?? sema.symbols.propertyType(for: symbol)
                        ?? sema.types.anyType
                    let result = arena.appendTemporary(type: resultType)
                    let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                    instructions.append(.call(
                        symbol: getterSymbol,
                        callee: interner.intern("get"),
                        arguments: [receiver],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                // Inline constant initializers only for immutable (val) properties.
                // Mutable (var) properties must always load from global store at runtime.
                if let symInfo = sema.symbols.symbol(symbol),
                   let constant = propertyConstantInitializers[symbol] ?? sema.symbols.constValueExprKind(for: symbol),
                   !symInfo.flags.contains(.mutable)
                {
                    let id = arena.appendExpr(constant, type: boundType)
                    instructions.append(.constValue(result: id, value: constant))
                    return id
                }
                // Synthetic top-level properties backed by a runtime bridge
                // have no global storage. Emit their zero-argument bridge
                // before the ordinary top-level property load path (for
                // example, the bare kotlinx.coroutines.isActive property).
                if let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property,
                   sema.symbols.extensionPropertyReceiverType(for: symbol) == nil,
                   let externalLinkName = sema.symbols.externalLinkName(for: symbol),
                   !externalLinkName.isEmpty
                {
                    let resultType = boundType
                        ?? sema.symbols.propertyType(for: symbol)
                        ?? sema.types.anyType
                    let result = arena.appendTemporary(type: resultType)
                    instructions.append(.call(
                        symbol: symbol,
                        callee: interner.intern(externalLinkName),
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                // Native stub properties with externalLinkName: call native function
                // directly via the implicit receiver, bypassing field-offset dispatch.
                // (e.g. kk_duration_inWholeNanoseconds accessed inside a bundled
                // Kotlin source extension getter body.)
                if let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property,
                   let externalLinkName = sema.symbols.externalLinkName(for: symbol),
                   !externalLinkName.isEmpty,
                   let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
                {
                    let resultType = boundType
                        ?? sema.symbols.propertyType(for: symbol)
                        ?? sema.types.anyType
                    let result = arena.appendTemporary(type: resultType)
                    instructions.append(.call(
                        symbol: symbol,
                        callee: interner.intern(externalLinkName),
                        arguments: [receiverExprID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                // Member property references inside class/object bodies must read
                // from the current implicit receiver instance rather than treating
                // the property symbol as a standalone value.
                //
                // Getter-only properties (`val size: Int get() = ...`) still occupy a
                // layout slot keyed by the property symbol, but that slot is never
                // written, so reading it here would yield garbage. Those dispatch to
                // the getter accessor in the branch below, matching the explicit
                // `this.size` path in CallLowerer+MemberPropertyReads.swift.
                if let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property || sym.kind == .field || sym.kind == .backingField,
                   let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let ownerKind = sema.symbols.symbol(ownerSymbol)?.kind,
                   ownerKind == .class || ownerKind == .interface,
                   sym.kind != .property
                       || sema.symbols.backingFieldSymbol(for: symbol) != nil
                       || !driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema),
                   let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                       sema.symbols.backingFieldSymbol(for: symbol) ?? symbol…22774 tokens truncated…    func storeFieldResult(_ value: KIRExprID) {
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_array_set"),
                            arguments: [receiverID, offsetExpr, value],
                            result: nil,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    }
                    if let callBinding = sema.bindings.callBindings[exprID],
                       let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                        if signature.returnType == sema.types.unitType {
                            _ = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType)
                        } else if let resultID = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType) {
                            storeFieldResult(resultID)
                        }
                    } else {
                        let resultID = appendBuiltinCompoundResult(
                            lhs: loadedValue,
                            lhsType: propType,
                            rhs: rhsID,
                            rhsType: arena.exprType(rhsID)
                        )
                        storeFieldResult(resultID)
                    }
                } else if driver.ctx.isMutableCaptureBoxed(symbol),
                          let loadedValue = loadMutableCaptureCellValue(
                              symbol: symbol,
                              resultType: {
                                  driver.ctx.localDeclaredType(for: symbol)
                                      ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                              }(),
                              sema: sema,
                              arena: arena,
                              interner: interner,
                              instructions: &instructions
                          )
                {
                    let symbolType = driver.ctx.localDeclaredType(for: symbol)
                        ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                    if let callBinding = sema.bindings.callBindings[exprID],
                       let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                        if signature.returnType == sema.types.unitType {
                            _ = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType)
                        } else if let resultID = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType) {
                            _ = storeMutableCaptureCellValue(
                                resultID,
                                for: symbol,
                                sema: sema,
                                arena: arena,
                                interner: interner,
                                instructions: &instructions
                            )
                        }
                    } else {
                        let resultID = appendBuiltinCompoundResult(
                            lhs: loadedValue,
                            lhsType: symbolType,
                            rhs: rhsID,
                            rhsType: arena.exprType(rhsID)
                        )
                        _ = storeMutableCaptureCellValue(
                            resultID,
                            for: symbol,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                    }
                } else if let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
                          let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                          let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                              sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
                          ]
                {
                    // Instance field accessed via implicit `this` receiver: must load/store
                    // through the object's field storage, mirroring the `.localAssign` write
                    // path and the `nameRef` read path. Falling through to the plain-local
                    // branch below would only update the compiler's local-value cache
                    // (used for real locals/params), never the field itself, so the write
                    // was silently dropped.
                    let fieldType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                    let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    let rawLoadedValue = arena.appendTemporary(type: fieldType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [receiverExprID, offsetExpr],
                        result: rawLoadedValue,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    let loadedValue = wrapLateinitReadIfNeeded(
                        rawLoadedValue,
                        symbol: symbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    func storeField(_ value: KIRExprID) {
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_array_set"),
                            arguments: [receiverExprID, offsetExpr, value],
                            result: nil,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    }
                    if let callBinding = sema.bindings.callBindings[exprID],
                       let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                        if signature.returnType == sema.types.unitType {
                            _ = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType)
                        } else if let resultID = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType) {
                            storeField(resultID)
                        }
                    } else {
                        let resultID = appendBuiltinCompoundResult(
                            lhs: loadedValue,
                            lhsType: fieldType,
                            rhs: rhsID,
                            rhsType: arena.exprType(rhsID)
                        )
                        storeField(resultID)
                    }
                } else {
                    if let storageID = driver.ctx.localValue(for: symbol) {
                        // Compute lhs op rhs and update storage in place so the value
                        // persists across loop iterations.
                        let symbolType = driver.ctx.localDeclaredType(for: symbol)
                            ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                        if let callBinding = sema.bindings.callBindings[exprID],
                           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                            if signature.returnType == sema.types.unitType {
                                _ = appendOperatorCompoundResult(lhs: storageID, rhs: rhsID, resultType: signature.returnType)
                            } else if let resultID = appendOperatorCompoundResult(lhs: storageID, rhs: rhsID, resultType: signature.returnType) {
                                instructions.append(.copy(from: resultID, to: storageID))
                            }
                        } else {
                            let resultID = appendBuiltinCompoundResult(
                                lhs: storageID,
                                lhsType: symbolType,
                                rhs: rhsID,
                                rhsType: arena.exprType(rhsID)
                            )
                            instructions.append(.copy(from: resultID, to: storageID))
                        }
                    } else {
                        // No existing local value — create a symbol reference as lhs
                        // so compound assignment still computes lhs op rhs.
                        let symbolType = driver.ctx.localDeclaredType(for: symbol)
                            ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                        let lhsID = arena.appendExpr(.symbolRef(symbol), type: symbolType)
                        instructions.append(.constValue(result: lhsID, value: .symbolRef(symbol)))
                        if let callBinding = sema.bindings.callBindings[exprID],
                           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                            if signature.returnType == sema.types.unitType {
                                _ = appendOperatorCompoundResult(lhs: lhsID, rhs: rhsID, resultType: signature.returnType)
                            } else if let resultID = appendOperatorCompoundResult(lhs: lhsID, rhs: rhsID, resultType: signature.returnType) {
                                driver.ctx.setLocalValue(resultID, for: symbol)
                            }
                        } else {
                            let resultID = appendBuiltinCompoundResult(
                                lhs: lhsID,
                                lhsType: symbolType,
                                rhs: rhsID,
                                rhsType: arena.exprType(rhsID)
                            )
                            driver.ctx.setLocalValue(resultID, for: symbol)
                        }
                    }
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .indexedCompoundAssign(_, receiverExpr, indices, valueExpr, _):
            return driver.callLowerer.lowerIndexedCompoundAssignExpr(
                exprID,
                receiverExpr: receiverExpr,
                indices: indices,
                valueExpr: valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .memberCompoundAssign(op, receiverExpr, calleeName, valueExpr, _):
            return driver.callLowerer.lowerMemberCompoundAssignExpr(
                exprID,
                op: op,
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                valueExpr: valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .throwExpr(valueExpr, _):
            let thrownValue = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            instructions.append(.rethrow(value: thrownValue))
            let unit = arena.appendExpr(.unit, type: sema.types.nothingType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .lambdaLiteral(params, bodyExpr, _, _):
            let allowsNonLocalReturn = driver.ctx.pendingLambdaNonLocalReturnAllowance
            driver.ctx.pendingLambdaNonLocalReturnAllowance = false
            return driver.lambdaLowerer.lowerLambdaLiteralExpr(
                exprID,
                params: params,
                bodyExpr: bodyExpr,
                allowsNonLocalReturn: allowsNonLocalReturn,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .callableRef(receiverExpr, memberName, _):
            // T::class  — emit a KClass metadata object via kk_kclass_create.
            // When used as `T::class.simpleName`, the memberCall lowerer
            // intercepts and emits a direct kk_type_token_simple_name call
            // instead.  For standalone `T::class` (assigned to a variable,
            // passed as an argument, etc.) the KClass box is needed.
            if memberName == KnownCompilerNames(interner: interner).className,
               let classRefTargetType = sema.bindings.classRefTargetType(for: exprID)
            {
                let intType = sema.types.make(.primitive(.int, .nonNull))

                // 1. Emit the type token.
                let tokenExpr: KIRExprID
                if case let .typeParam(typeParam) = sema.types.kind(of: classRefTargetType) {
                    let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParam.symbol)
                    tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
                    instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
                } else {
                    let encoded = RuntimeTypeCheckToken.encode(type: classRefTargetType, sema: sema, interner: interner)
                    tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
                }

                // 2. Emit the name-hint.
                // kk_kclass_create ABI expects (Int, Int) — both parameters are
                // intptr_t.  The name hint is either a runtime string pointer
                // (passed as an int-typed string literal that codegen materialises
                // into a pointer bit-pattern) or 0 when no name is available.
                // We always use intType here to stay consistent with the ABI.
                let nameHintExpr: KIRExprID
                if let name = RuntimeTypeCheckToken.simpleName(of: classRefTargetType, sema: sema, interner: interner) {
                    let internedName = interner.intern(name)
                    nameHintExpr = arena.appendExpr(.stringLiteral(internedName), type: intType)
                    instructions.append(.constValue(result: nameHintExpr, value: .stringLiteral(internedName)))
                } else {
                    nameHintExpr = arena.appendExpr(.intLiteral(0), type: intType)
                    instructions.append(.constValue(result: nameHintExpr, value: .intLiteral(0)))
                }

                // 3. Call kk_kclass_create to produce a KClass metadata object.
                // Prefer the sema-bound KClass<T> type and fall back to
                // KClass<classRefTargetType> so the result always carries the
                // precise generic parameter instead of degrading to Any.
                let kClassFallback = sema.types.makeKClassType(argument: classRefTargetType)
                let result = arena.appendTemporary(type: boundType ?? kClassFallback
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_kclass_create"),
                    arguments: [tokenExpr, nameHintExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))

                // STDLIB-REFLECT-067: A standalone `T::class` box may later be
                // queried for metadata-backed members (e.g. `val k = Foo::class;
                // k.isData`). The member-call lowerer only registers metadata when
                // the receiver is a literal class-ref, so register it here too,
                // reusing the same `tokenExpr` so the box and its metadata share a
                // type token. No-op for reified type parameters / built-ins.
                driver.callLowerer.emitClassLiteralMetadataRegistration(
                    classRefTargetType: classRefTargetType,
                    typeTokenExpr: tokenExpr,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                return result
            }
            return driver.lambdaLowerer.lowerCallableRefExpr(
                exprID,
                receiverExpr: receiverExpr,
                memberName: memberName,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .objectLiteral(superTypes, declID, _):
            return driver.objectLiteralLowerer.lowerObjectLiteralExpr(
                exprID,
                superTypes: superTypes,
                declID: declID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .localNominalDecl(declID, _):
            return driver.objectLiteralLowerer.lowerLocalNominalDeclExpr(
                exprID,
                declID: declID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .whenExpr(subject, branches, elseExpr, _):
            return driver.controlFlowLowerer.lowerWhenExpr(
                exprID,
                subject: subject,
                branches: branches,
                elseExpr: elseExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .blockExpr(statements, trailingExpr, _):
            for stmt in statements {
                let loweredStmt = lowerExpr(
                    stmt,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                // If the statement is a terminator (return/throw), stop lowering
                if driver.controlFlowLowerer.isTerminatedExpr(loweredStmt, arena: arena, sema: sema) {
                    return loweredStmt
                }
            }
            if let trailingExpr {
                return lowerExpr(
                    trailingExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .superRef:
            if let receiverExprID = driver.ctx.activeImplicitReceiverExprID() {
                return receiverExprID
            }
            let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .thisRef(label, _):
            if let receiverSymbol = sema.bindings.identifierSymbol(for: exprID),
               let receiverExprID = driver.ctx.localValue(for: receiverSymbol)
            {
                return receiverExprID
            }
            if let label,
               let receiverExprID = driver.ctx.qualifiedThisReceiverExprID(for: label)
            {
                return receiverExprID
            }
            if let receiverExprID = driver.ctx.activeImplicitReceiverExprID() {
                return receiverExprID
            }
            let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .inExpr(lhsExpr, rhsExpr, _):
            let lhsID = lowerExpr(
                lhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            return lowerContainsCheck(
                exprID: exprID,
                lhsID: lhsID,
                lhsExpr: lhsExpr,
                rhsExpr: rhsExpr,
                negated: false,
                boundType: boundType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .notInExpr(lhsExpr, rhsExpr, _):
            let lhsID = lowerExpr(
                lhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            return lowerContainsCheck(
                exprID: exprID,
                lhsID: lhsID,
                lhsExpr: lhsExpr,
                rhsExpr: rhsExpr,
                negated: true,
                boundType: boundType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .destructuringDecl(names, _, initializer, _):
            // Lower: val (a, b) = expr  →  tmp = expr; a = tmp.component1(); b = tmp.component2()
            let rhsID = lowerExpr(
                initializer, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let rhsType = sema.bindings.exprTypes[initializer] ?? sema.types.anyType
            let nonNullRhsType = sema.types.makeNonNullable(rhsType)
            for (index, name) in names.enumerated() {
                guard let name else {
                    // Underscore — skip
                    continue
                }
                let componentIndex = index + 1
                let componentName = interner.intern("component\(componentIndex)")

                // Resolve componentN to externalLinkName when available (Pair, Triple, List, etc.)
                let memberCandidates = TypeCheckHelpers().collectMemberFunctionCandidates(
                    named: componentName,
                    receiverType: nonNullRhsType,
                    sema: sema,
                    interner: interner
                )
                // Sema's chosen callee wins: `componentN` is an overloaded name across
                // Pair/Triple, user extensions and bundled stdlib extensions, so the
                // symbol has to travel to codegen instead of being re-resolved by name.
                let chosenCallee = sema.bindings.destructuringComponentCallee(
                    for: exprID,
                    index: index
                ) ?? memberCandidates.first
                let calleeName: InternedString = if let chosenCallee,
                                                    let linkName = sema.symbols.externalLinkName(for: chosenCallee),
                                                    !linkName.isEmpty
                {
                    interner.intern(linkName)
                } else {
                    componentName
                }

                // Look up the symbol defined by Sema for this variable first,
                // so we can use its per-component type (not the expression-level Unit type)
                let candidates = sema.symbols.lookupAll(fqName: [
                    interner.intern("__destructuring_\(exprID.rawValue)"),
                    name,
                ])
                let componentType = candidates.first.flatMap { sema.symbols.propertyType(for: $0) } ?? sema.types.anyType
                let componentResult = arena.appendTemporary(type: componentType)
                let calleeSymbol: SymbolID? = chosenCallee.flatMap { callee in
                    sema.symbols.isSourceBackedSymbol(callee) ? callee : nil
                }
                instructions.append(.call(
                    symbol: calleeSymbol,
                    callee: calleeName,
                    arguments: [rhsID],
                    result: componentResult,
                    canThrow: false,
                    thrownResult: nil
                ))

                // Bind the destructured variable to the component result
                if let symbol = candidates.first {
                    driver.ctx.setLocalValue(componentResult, for: symbol)
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .forDestructuringExpr(names, iterableExpr, bodyExpr, _):
            // Lower as a regular for-loop, but inside the body, destructure the element
            // Delegate to control flow lowerer for loop structure
            return driver.controlFlowLowerer.lowerForDestructuringExpr(
                exprID,
                names: names,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
    }

    /// Lowers `lhs in rhs` / `lhs !in rhs` given an already-lowered `lhsID`.
    /// `when` branch conditions (`ControlFlowLowerer+WhenExpr.swift`) reuse the
    /// subject's single lowering here instead of re-lowering `lhsExpr`, which
    /// would re-evaluate a side-effecting subject once per `in`/`!in` branch.
    func lowerContainsCheck(
        exprID: ExprID,
        lhsID: KIRExprID,
        lhsExpr: ExprID,
        rhsExpr: ExprID,
        negated: Bool,
        boundType: TypeID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let rhsID = lowerExpr(
            rhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
        )
        // KSP-1523: UInt used to get its own branch here (`kk_uint_range_contains`),
        // gated on `rhsType == uintType` — but `rhsType` is the range's own type
        // (e.g. UIntRange), never its element type, so that comparison was always
        // false. UInt now falls through to the same `appendContainsCall` path as
        // every other range, which resolves to the shared `__kk_range_contains`
        // bridge (safe: UInt always fits the Int64 fields it operates on).
        let floatingPointCallee = floatingPointRangeContainsCallee(
            for: rhsExpr, value: lhsExpr, sema: sema, interner: interner
        )

        if !negated {
            let result = arena.appendTemporary(type: boundType ?? boolType)
            if let floatingPointCallee {
                let floatingPointValueID = floatingPointRangeContainsValueID(
                    lhsID, valueExpr: lhsExpr, callee: floatingPointCallee,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: floatingPointCallee,
                    arguments: [rhsID, floatingPointValueID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                appendContainsCall(
                    exprID: exprID,
                    elementID: lhsID,
                    containerID: rhsID,
                    resultID: result,
                    sema: sema,
                    interner: interner,
                    instructions: &instructions
                )
            }
            return result
        }

        let notInContainsCallee: String = if let floatingPointCallee {
            interner.resolve(floatingPointCallee)
        } else {
            "kk_op_contains"
        }
        let containsResult = arena.appendTemporary(type: boolType)
        if notInContainsCallee.hasPrefix("__kk_") {
            let floatingPointValueID: KIRExprID = if let floatingPointCallee {
                floatingPointRangeContainsValueID(
                    lhsID, valueExpr: lhsExpr, callee: floatingPointCallee,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
            } else {
                lhsID
            }
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(notInContainsCallee),
                arguments: [rhsID, floatingPointValueID],
                result: containsResult,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            appendContainsCall(
                exprID: exprID,
                elementID: lhsID,
                containerID: rhsID,
                resultID: containsResult,
                sema: sema,
                interner: interner,
                instructions: &instructions
            )
        }
        let result = arena.appendTemporary(type: boundType ?? boolType)
        let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
        instructions.append(.binary(op: .equal, lhs: containsResult, rhs: falseValue, result: result))
        return result
    }

    /// Emits a contains call instruction, dispatching to a user-defined operator fun contains
    /// if sema recorded a CallBinding, or falling back to the kk_op_contains runtime stub.
    private func appendContainsCall(
        exprID: ExprID,
        elementID: KIRExprID,
        containerID: KIRExprID,
        resultID: KIRExprID,
        sema: SemaModule,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        // Dispatch to a source-backed operator fun contains when available
        // (including range/progression members, STDLIB-OP-032), otherwise use the
        // generic kk_op_contains runtime stub.
        if
           let callBinding = sema.bindings.callBindings[exprID],
           callBinding.chosenCallee != .invalid,
           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
           signature.receiverType != nil
        {
            let calleeName: InternedString = if let linkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                                                !linkName.isEmpty
            {
                interner.intern(linkName)
            } else if let sym = sema.symbols.symbol(callBinding.chosenCallee) {
                sym.name
            } else {
                interner.intern("contains")
            }
            instructions.append(.call(
                symbol: callBinding.chosenCallee,
                callee: calleeName,
                arguments: [containerID, elementID],
                result: resultID,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_contains"),
                arguments: [containerID, elementID],
                result: resultID,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }

    private func floatingPointRangeContainsCallee(
        for rangeExpr: ExprID,
        value valueExpr: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        let elementType = sema.bindings.floatingPointRangeElementType(forExpr: rangeExpr)
            ?? sema.bindings.identifierSymbol(for: rangeExpr).flatMap {
                sema.bindings.floatingPointRangeElementType(forSymbol: $0)
        }
        guard let elementType else { return nil }
        let valueType = sema.types.makeNonNullable(
            sema.bindings.exprTypes[valueExpr] ?? sema.types.anyType
        )
        if elementType == sema.types.floatType {
            guard valueType == sema.types.floatType else { return nil }
            return interner.intern("__kk_float_range_contains")
        }
        if elementType == sema.types.doubleType {
            guard valueType == sema.types.doubleType || valueType == sema.types.floatType else { return nil }
            return interner.intern("__kk_double_range_contains")
        }
        return nil
    }

    private func floatingPointRangeContainsValueID(
        _ valueID: KIRExprID,
        valueExpr: ExprID,
        callee: InternedString,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard callee == interner.intern("__kk_double_range_contains"),
              sema.types.makeNonNullable(sema.bindings.exprTypes[valueExpr] ?? sema.types.anyType)
                  == sema.types.floatType
        else {
            return valueID
        }
        let converted = arena.appendTemporary(type: sema.types.doubleType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_float_to_double_bits"),
            arguments: [valueID],
            result: converted,
            canThrow: false,
            thrownResult: nil
        ))
        return converted
    }

    /// Resolves the *effective* delegate for a local custom-delegate declaration
    /// (BUG-146). When the delegate factory exposes a `provideDelegate` operator,
    /// the actual delegate is its return value — the same rule member/top-level
    /// delegated properties follow in KIRLoweringDriver+ProvideDelegate.swift.
    /// Emits `rawDelegate.provideDelegate(null, KProperty("x"))` and returns the
    /// result. When no `provideDelegate` is present, returns `rawDelegateID`
    /// unchanged (the delegate factory instance is itself the delegate).
    func lowerLocalProvideDelegateIfNeeded(
        symbol: SymbolID,
        rawDelegateID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard sema.symbols.hasProvideDelegate(for: symbol),
              let provideDelegateSymbol = sema.symbols.delegateProvideDelegateSymbol(for: symbol)
        else {
            return rawDelegateID
        }
        let provideArgs = driver.memberLowerer.buildLocalDelegateAccessorArgs(
            localSymbol: symbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let providedExprID = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            symbol: provideDelegateSymbol,
            callee: interner.intern("provideDelegate"),
            arguments: [rawDelegateID] + provideArgs,
            result: providedExprID,
            canThrow: false,
            thrownResult: nil
        ))
        return providedExprID
    }

    /// Reads a delegated local's current value by calling its resolved
    /// `getValue` operator fresh, rather than reusing whatever was computed
    /// at the declaration (which doesn't exist for delegates -- see the
    /// `.localDecl` case above). Real Kotlin delegated properties call
    /// getValue at every read site, and for `var` delegates observing writes
    /// (`Delegates.observable`, or a custom delegate a write may veto)
    /// depends on that: reusing a cached read would silently miss any
    /// change the delegate itself made to the stored value.
    /// Returns `nil` when `symbol` is not a delegated local.
    func readLocalDelegateValue(
        symbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let delegateStorageID = driver.ctx.localDelegateStorage(for: symbol),
              let getValueSymbol = sema.symbols.delegateGetValueSymbol(for: symbol)
        else {
            return nil
        }
        let getterArgs = driver.memberLowerer.buildLocalDelegateAccessorArgs(
            localSymbol: symbol, sema: sema, arena: arena, interner: interner,
            instructions: &instructions
        )
        let propertyType = driver.ctx.localDeclaredType(for: symbol)
            ?? sema.symbols.propertyType(for: symbol)
            ?? sema.types.anyType
        let resultExprID = arena.appendTemporary(type: propertyType)
        instructions.append(driver.memberLowerer.dispatchedDelegateMemberCall(
            symbol: getValueSymbol,
            callee: interner.intern("getValue"),
            receiver: delegateStorageID,
            extraArguments: getterArgs,
            result: resultExprID,
            sema: sema,
            interner: interner
        ))
        return resultExprID
    }

    /// Whether the expression is a plain read of a variable (`b` in `val a = b`).
    /// Such initializers must be snapshotted into their own register instead of
    /// aliasing the source variable's storage.
    func isBareVariableRead(_ exprID: ExprID, ast: ASTModule) -> Bool {
        if case .nameRef = ast.arena.expr(exprID) {
            return true
        }
        return false
    }

}
