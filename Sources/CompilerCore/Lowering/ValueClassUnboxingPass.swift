/// This pass must run **before** PropertyLoweringPass and ABILoweringPass.
final class ValueClassUnboxingPass: LoweringPass, ParallelLoweringPass {
    static let name = "ValueClassUnboxing"
    static let requiredStage: KIRStage = .desugared
    static let producedStage: KIRStage = .valueClassUnboxed

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        guard let sema = ctx.sema else { return false }
        let symbols = sema.symbols
        for decl in module.arena.declarations {
            guard case let .nominalType(nominal) = decl else { continue }
            guard let sym = symbols.symbol(nominal.symbol),
                  sym.flags.contains(.valueType),
                  symbols.effectiveValueClassUnderlyingType(for: nominal.symbol) != nil
            else { continue }
            return true
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        let symbols = sema.symbols
        let types = sema.types

        var valueClassCtors: Set<SymbolID> = []
        var secondaryValueClassCtors: Set<SymbolID> = []
        var valueClassSymbols: Set<SymbolID> = []

        for decl in module.arena.declarations {
            guard case let .nominalType(nominal) = decl else { continue }
            guard let sym = symbols.symbol(nominal.symbol),
                  sym.flags.contains(.valueType),
                  symbols.effectiveValueClassUnderlyingType(for: nominal.symbol) != nil
            else { continue }

            valueClassSymbols.insert(nominal.symbol)

            let children = symbols.children(ofFQName: sym.fqName)
            for childID in children {
                guard let child = symbols.symbol(childID) else { continue }
                if child.kind == .constructor {
                    valueClassCtors.insert(childID)
                    if let owner = symbols.parentSymbol(for: childID),
                       let ownerInfo = symbols.symbol(owner),
                       let childDeclSite = child.declSite,
                       childDeclSite != ownerInfo.declSite
                    {
                        secondaryValueClassCtors.insert(childID)
                    }
                }
            }
        }

        guard !valueClassSymbols.isEmpty else {
            module.recordLowering(Self.name)
            return
        }

        let kk_object_new = ctx.interner.intern("kk_object_new")
        let kk_array_get_inbounds = ctx.interner.intern("kk_array_get_inbounds")
        let kk_array_set = ctx.interner.intern("kk_array_set")

        // A value-class constructor whose body does more than store its
        // underlying field carries observable work (init blocks, parameter
        // validation) that must survive unboxing. Such ctors keep their
        // `kk_object_new` + `<init>` call sequence; the pass only appends the
        // raw-representation copy afterwards.
        var ctorsRequiringExecution: Set<SymbolID> = []
        var ctorUnderlyingFieldOffset: [SymbolID: Int64] = [:]
        var executingCtorThisSymbols: Set<SymbolID> = []
        // `V()` lowers to `call V$default(alloc, mask)`: the synthetic
        // default-arg stub's symbol differs from the constructor symbol.
        var valueClassDefaultStubToCtor: [SymbolID: SymbolID] = [:]
        for ctorSymbol in valueClassCtors {
            valueClassDefaultStubToCtor[
                SyntheticSymbolScheme.defaultStubSymbol(for: ctorSymbol)
            ] = ctorSymbol
        }
        for decl in module.arena.declarations {
            guard case let .function(function) = decl,
                  valueClassCtors.contains(function.symbol)
            else { continue }
            // constValue result -> literal, so `kk_array_set(this, offset, _)`
            // can reveal where the underlying field lives.
            var literalByExpr: [KIRExprID: Int64] = [:]
            for instruction in function.body {
                if case let .constValue(resultExpr, value) = instruction,
                   case let .intLiteral(literal) = value
                {
                    literalByExpr[resultExpr] = literal
                }
            }
            for instruction in function.body {
                if case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                   callee == kk_array_set, arguments.count == 3,
                   let offset = literalByExpr[arguments[1]]
                {
                    ctorUnderlyingFieldOffset[function.symbol] = offset
                }
            }
            if function.body.contains(where: {
                !$0.isPureValueClassFieldInit(kk_array_set: kk_array_set)
            }) {
                ctorsRequiringExecution.insert(function.symbol)
                if let thisParam = function.params.first {
                    executingCtorThisSymbols.insert(thisParam.symbol)
                }
            }
        }

        // Secondary constructors delegate to the primary constructor, which
        // writes the one underlying field into the temporary heap box. Reuse
        // that field's layout offset when extracting the raw value after a
        // secondary constructor has executed.
        var underlyingFieldOffsetByOwner: [SymbolID: Int64] = [:]
        for (ctorSymbol, offset) in ctorUnderlyingFieldOffset
            where !secondaryValueClassCtors.contains(ctorSymbol)
        {
            guard let owner = symbols.parentSymbol(for: ctorSymbol) else { continue }
            underlyingFieldOffsetByOwner[owner] = offset
        }
        for ctorSymbol in secondaryValueClassCtors where ctorUnderlyingFieldOffset[ctorSymbol] == nil {
            guard let owner = symbols.parentSymbol(for: ctorSymbol),
                  let offset = underlyingFieldOffsetByOwner[owner]
            else {
                continue
            }
            ctorUnderlyingFieldOffset[ctorSymbol] = offset
        }
        let interner = ctx.interner
        let boxingCalleeTable = BoxingCalleeTable(interner: interner)

        module.arena.transformFunctions { function in
            var updated = function
            let rewritten = self.rewriteBody(
                function.body,
                locations: function.instructionLocations,
                module: module,
                arena: module.arena,
                interner: interner,
                types: types,
                symbols: symbols,
                valueClassCtors: valueClassCtors,
                valueClassSymbols: valueClassSymbols,
                kk_object_new: kk_object_new,
                kk_array_get_inbounds: kk_array_get_inbounds,
                boxingCalleeTable: boxingCalleeTable,
                ctorsRequiringExecution: ctorsRequiringExecution,
                ctorUnderlyingFieldOffset: ctorUnderlyingFieldOffset,
                secondaryValueClassCtors: secondaryValueClassCtors,
                executingCtorThisSymbols: executingCtorThisSymbols,
                valueClassDefaultStubToCtor: valueClassDefaultStubToCtor
            )
            updated.replaceBody(rewritten.instructions, locations: rewritten.locations)
            return updated
        }

        module.recordLowering(Self.name)
    }

    /// Nullable value-class-typed expressions are included: a
    /// `kk_array_get_inbounds` property read only ever appears on a receiver
    /// Kotlin's type checker has already proven non-null at that point (e.g.
    /// the non-null branch of a safe call, or the result of `maxByOrNull`
    /// right after its `jumpIfNotNull` guard) — the KIR type itself just
    /// hasn't been narrowed. Requiring `.nonNull` here made those reads fall
    /// through to the generic call fallback and crash on the unboxed raw
    /// value instead of being rewritten to a plain copy.
    private func isValueClassExpr(
        _ expr: KIRExprID,
        arena: KIRArena,
        types: TypeSystem,
        symbols: SymbolTable,
        valueClassSymbols: Set<SymbolID>,
        allowTypeParameterUpperBound: Bool = false
    ) -> Bool {
        guard let type = arena.exprType(expr) else { return false }
        let classSymbol: SymbolID?
        switch types.kind(of: type) {
        case let .classType(classType):
            classSymbol = classType.classSymbol
        case let .typeParam(typeParameter) where allowTypeParameterUpperBound:
            // A type parameter bounded by a value class still uses that
            // value class's unboxed representation for direct property reads.
            classSymbol = symbols.typeParameterUpperBounds(for: typeParameter.symbol).compactMap { bound -> SymbolID? in
                guard case let .classType(classType) = types.kind(of: bound),
                      valueClassSymbols.contains(classType.classSymbol)
                else { return nil }
                return classType.classSymbol
            }.first
        default:
            classSymbol = nil
        }
        if let classSymbol, valueClassSymbols.contains(classSymbol) {
            return true
        }
        return false
    }

    /// KUU-3251: a `kk_array_get_inbounds` receiver whose KIR type is a
    /// *nullable* `V?` (or an erased type-parameter slot bounded by a value
    /// class) carries the `kk_tag_value_class_box` tagged handle, not the
    /// unboxed payload. Rewriting the read to a bare copy would alias the box
    /// itself as the underlying field — `println(s?.x)` then dispatches
    /// `S.toString` on the box and recurses (`S(x=S(x=…`). Emit the matching
    /// `kk_unbox_*`/`kk_string_to_flat` payload extraction instead. A
    /// non-null `V` receiver already holds the unboxed payload, and value
    /// classes whose underlying type has no boxing callee (reference-type
    /// payloads) stay on the plain copy — their `V?` slot *is* the payload.
    private func valueClassPayloadUnboxCallee(
        for receiver: KIRExprID,
        arena: KIRArena,
        types: TypeSystem,
        symbols: SymbolTable,
        valueClassSymbols: Set<SymbolID>,
        boxingCalleeTable: BoxingCalleeTable
    ) -> InternedString? {
        guard let receiverType = arena.exprType(receiver) else { return nil }
        let classSymbol: SymbolID?
        switch types.kind(of: receiverType) {
        case let .classType(classType):
            // Non-null receivers already hold the unboxed payload.
            guard classType.nullability != .nonNull else { return nil }
            classSymbol = classType.classSymbol
        case let .typeParam(typeParameter):
            // Generic slots are erased, so a type-parameter receiver bounded
            // by a value class carries the tagged box at any nullability.
            classSymbol = symbols.typeParameterUpperBounds(for: typeParameter.symbol).compactMap { bound -> SymbolID? in
                guard case let .classType(boundClass) = types.kind(of: bound),
                      valueClassSymbols.contains(boundClass.classSymbol)
                else { return nil }
                return boundClass.classSymbol
            }.first
        default:
            classSymbol = nil
        }
        guard let classSymbol,
              valueClassSymbols.contains(classSymbol),
              let underlyingType = symbols.effectiveValueClassUnderlyingType(for: classSymbol)
        else { return nil }
        return boxingCalleeTable.unboxCallee(
            for: types.kind(of: underlyingType),
            requireNonNull: true,
            preferStaticPrimitive: true
        )
    }

    /// KUU-3115: a `V?` receiver of a value class whose underlying payload can
    /// itself be null holds a nominal `RuntimeObjectBox` — the inbounds read
    /// *is* the payload load, so it must be kept rather than rewritten to a
    /// bare copy (which would alias the box as the `String?` payload).
    private func isNullableUnderlyingValueClassReceiver(
        _ expr: KIRExprID,
        arena: KIRArena,
        types: TypeSystem,
        symbols: SymbolTable
    ) -> Bool {
        guard let receiverType = arena.exprType(expr),
              case let .classType(classType) = types.kind(of: receiverType),
              classType.nullability != .nonNull
        else { return false }
        return nullableUnderlyingValueClassSymbol(
            of: types.kind(of: types.makeNonNullable(receiverType)),
            types: types,
            symbols: symbols
        ) != nil
    }

    private func rewriteBody(
        _ body: [KIRInstruction],
        locations: [SourceRange?],
        module: KIRModule,
        arena: KIRArena,
        interner: StringInterner,
        types: TypeSystem,
        symbols: SymbolTable,
        valueClassCtors: Set<SymbolID>,
        valueClassSymbols: Set<SymbolID>,
        kk_object_new: InternedString,
        kk_array_get_inbounds: InternedString,
        boxingCalleeTable: BoxingCalleeTable,
        ctorsRequiringExecution: Set<SymbolID>,
        ctorUnderlyingFieldOffset: [SymbolID: Int64],
        secondaryValueClassCtors: Set<SymbolID>,
        executingCtorThisSymbols: Set<SymbolID>,
        valueClassDefaultStubToCtor: [SymbolID: SymbolID]
    ) -> (instructions: [KIRInstruction], locations: [SourceRange?]) {
        // The KIR pattern for `val m = Meter(42)` is:
        //   constValue slotCount = 1
        //   constValue classID = ...
        //   call kk_object_new(slotCount, classID) -> allocObj     [symbol: nil]
        //   ... (possibly kk_type_register_super/iface calls) ...
        //   call <init>(allocObj, 42) -> result                     [symbol: ctor]

        var allocExprs: Set<KIRExprID> = []
        var allocConstExprs: Set<KIRExprID> = []
        var classIDExprs: Set<KIRExprID> = []
        var allocArgsByExpr: [KIRExprID: [KIRExprID]] = [:]

        for instruction in body {
            if case let .call(_, callee, arguments, result, _, _, _, _) = instruction,
               callee == kk_object_new,
               let result,
               isValueClassExpr(
                   result, arena: arena, types: types, symbols: symbols,
                   valueClassSymbols: valueClassSymbols
               )
            {
                allocExprs.insert(result)
                allocArgsByExpr[result] = arguments
                // arguments[0] = slotCount, arguments[1] = classID
                if arguments.count >= 1 {
                    allocConstExprs.insert(arguments[0])
                }
                if arguments.count >= 2 {
                    allocConstExprs.insert(arguments[1])
                    classIDExprs.insert(arguments[1])
                }
            }
        }

        // Allocations feeding a constructor that must still run are kept
        // together with their constants and registration calls — the
        // constructor body dereferences `this`.
        var keptAllocExprs: Set<KIRExprID> = []
        var keptAllocConstExprs: Set<KIRExprID> = []
        var keptClassIDExprs: Set<KIRExprID> = []
        for instruction in body {
            guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                  let symbol,
                  let alloc = arguments.first, allocExprs.contains(alloc)
            else { continue }
            let isStubCall = valueClassDefaultStubToCtor[symbol] != nil
            let ctorSymbol = valueClassCtors.contains(symbol)
                ? symbol : valueClassDefaultStubToCtor[symbol]
            // Receiver-only calls and $default stubs must execute regardless:
            // the payload is not among the arguments, so eliding the call
            // loses the value too.
            guard let ctorSymbol,
                  ctorsRequiringExecution.contains(ctorSymbol)
                    || isStubCall
                    || (arguments.count == 1 && ctorUnderlyingFieldOffset[ctorSymbol] != nil)
            else { continue }
            keptAllocExprs.insert(alloc)
            if let allocArgs = allocArgsByExpr[alloc] {
                keptAllocConstExprs.formUnion(allocArgs)
                if allocArgs.count >= 2 {
                    keptClassIDExprs.insert(allocArgs[1])
                }
            }
        }
        let elidableClassIDExprs = classIDExprs.subtracting(keptClassIDExprs)

        var typeRegisterConstExprs: Set<KIRExprID> = []
        for instruction in body {
            if case let .call(_, callee, arguments, result, _, _, _, _) = instruction,
               let result
            {
                let calleeName = interner.resolve(callee)
                if calleeName.hasPrefix("kk_type_register_") {
                    // arguments[0] = childExpr (classID), arguments[1] = parentExpr
                    if arguments.count >= 1 {
                        for classIDExpr in elidableClassIDExprs {
                            if let classIDKind = arena.expr(classIDExpr),
                               let childKind = arena.expr(arguments[0]),
                               classIDKind == childKind
                            {
                                typeRegisterConstExprs.insert(result)
                                if arguments.count >= 2 {
                                    typeRegisterConstExprs.insert(arguments[1])
                                }
                                typeRegisterConstExprs.insert(arguments[0])
                            }
                        }
                    }
                }
            }
        }

        var result: [KIRInstruction] = []
        var resultLocations: [SourceRange?] = []
        result.reserveCapacity(body.count)
        resultLocations.reserveCapacity(body.count)

        func appendSecondaryValueClassResultExtraction(
            boxedReceiver: KIRExprID,
            ctorSymbol: SymbolID,
            offset: Int64,
            callResult: KIRExprID,
            location: SourceRange?
        ) -> Bool {
            guard let owner = symbols.parentSymbol(for: ctorSymbol),
                  let underlyingType = symbols.effectiveValueClassUnderlyingType(for: owner)
            else {
                return false
            }

            // The allocation is still a heap box while the secondary
            // constructor body runs. Keep its reference representation at the
            // erased array access boundary; the constructor result becomes the
            // raw underlying payload below.
            arena.setExprType(types.nullableAnyType, for: boxedReceiver)
            let offsetExpr = arena.appendExpr(.intLiteral(offset), type: types.intType)
            let payloadExpr = arena.appendTemporary(type: underlyingType)
            result.append(.constValue(result: offsetExpr, value: .intLiteral(offset)))
            resultLocations.append(location)
            result.append(.call(
                callee: kk_array_get_inbounds,
                arguments: [boxedReceiver, offsetExpr],
                result: payloadExpr,
                canThrow: false
            ))
            resultLocations.append(location)
            result.append(.copy(from: payloadExpr, to: callResult))
            resultLocations.append(location)
            return true
        }

        for (index, instruction) in body.enumerated() {
            let location = index < locations.count ? locations[index] : nil
            switch instruction {
            case let .call(_, callee, _, callResult, _, _, _, _)
                where callee == kk_object_new
                    && callResult != nil
                    && allocExprs.contains(callResult!)
                    && !keptAllocExprs.contains(callResult!):
                result.append(.nop)
                resultLocations.append(location)
                continue

            case let .constValue(constResult, _)
                where allocConstExprs.contains(constResult)
                    && !keptAllocConstExprs.contains(constResult):
                result.append(.nop)
                resultLocations.append(location)
                continue

            case let .call(_, callee, arguments, _, _, _, _, _)
                where {
                    let name = interner.resolve(callee)
                    guard name.hasPrefix("kk_type_register_") else { return false }
                    guard arguments.count >= 1 else { return false }
                    for classIDExpr in elidableClassIDExprs {
                        if let classIDKind = arena.expr(classIDExpr),
                           let childKind = arena.expr(arguments[0]),
                           classIDKind == childKind
                        {
                            return true
                        }
                    }
                    return false
                }():
                result.append(.nop)
                resultLocations.append(location)
                continue

            case let .constValue(constResult, _)
                where typeRegisterConstExprs.contains(constResult):
                result.append(.nop)
                resultLocations.append(location)
                continue

            case let .call(symbol, callee, arguments, callResult, canThrow, thrownResult, isSuperCall, qualifiedSuperType):
                let directCtor = symbol.map { valueClassCtors.contains($0) } ?? false
                let stubCtorSymbol = symbol.flatMap { valueClassDefaultStubToCtor[$0] }
                if let symbol, let callResult, let ctorSymbol = directCtor ? symbol : stubCtorSymbol {
                    let mustExecute = ctorsRequiringExecution.contains(ctorSymbol)
                    if !directCtor, let alloc = arguments.first, allocExprs.contains(alloc) {
                        if secondaryValueClassCtors.contains(ctorSymbol),
                           let offset = ctorUnderlyingFieldOffset[ctorSymbol],
                           let owner = symbols.parentSymbol(for: ctorSymbol),
                           symbols.effectiveValueClassUnderlyingType(for: owner) != nil
                        {
                            result.append(.call(
                                symbol: symbol,
                                callee: callee,
                                arguments: arguments,
                                result: nil,
                                canThrow: canThrow,
                                thrownResult: thrownResult,
                                isSuperCall: isSuperCall,
                                qualifiedSuperType: qualifiedSuperType
                            ))
                            resultLocations.append(location)
                            _ = appendSecondaryValueClassResultExtraction(
                                boxedReceiver: alloc,
                                ctorSymbol: ctorSymbol,
                                offset: offset,
                                callResult: callResult,
                                location: location
                            )
                            continue
                        }
                        // `V$default(alloc, ...)`: the stub resolves defaults
                        // internally, so the payload is not among the call
                        // arguments — keep the call and read the underlying
                        // field back out of the allocated box.
                        result.append(instruction)
                        resultLocations.append(location)
                        // Nullable-underlying value-class stubs return the raw
                        // payload through their function ABI. Extracting the
                        // same field from that result treats the payload as the
                        // wrapper and corrupts subsequent member access (KUU-3407).
                        let returnsNullableUnderlyingValueClass = arena.exprType(callResult)
                            .map { nullableUnderlyingValueClassSymbol(
                                of: types.kind(of: $0), types: types, symbols: symbols
                            ) != nil } ?? false
                        if !returnsNullableUnderlyingValueClass,
                           let offset = ctorUnderlyingFieldOffset[ctorSymbol]
                        {
                            if secondaryValueClassCtors.contains(ctorSymbol),
                               appendSecondaryValueClassResultExtraction(
                                   boxedReceiver: alloc,
                                   ctorSymbol: ctorSymbol,
                                   offset: offset,
                                   callResult: callResult,
                                   location: location
                               )
                            {
                                continue
                            }
                            let offsetExpr = arena.appendExpr(.intLiteral(offset), type: nil)
                            result.append(.constValue(result: offsetExpr, value: .intLiteral(offset)))
                            resultLocations.append(location)
                            result.append(.call(
                                callee: kk_array_get_inbounds,
                                arguments: [callResult, offsetExpr],
                                result: callResult,
                                canThrow: false
                            ))
                            resultLocations.append(location)
                        }
                        continue
                    }
                    if let boxedReceiver = arguments.first,
                       allocExprs.contains(boxedReceiver),
                       secondaryValueClassCtors.contains(ctorSymbol),
                       let offset = ctorUnderlyingFieldOffset[ctorSymbol],
                       let owner = symbols.parentSymbol(for: ctorSymbol),
                       symbols.effectiveValueClassUnderlyingType(for: owner) != nil
                    {
                        // Secondary constructors can have multiple explicit
                        // parameters. Keep their body call and extract the
                        // delegated primary constructor's payload afterward.
                        result.append(.call(
                            symbol: symbol,
                            callee: callee,
                            arguments: arguments,
                            result: nil,
                            canThrow: canThrow,
                            thrownResult: thrownResult,
                            isSuperCall: isSuperCall,
                            qualifiedSuperType: qualifiedSuperType
                        ))
                        resultLocations.append(location)
                        _ = appendSecondaryValueClassResultExtraction(
                            boxedReceiver: boxedReceiver,
                            ctorSymbol: ctorSymbol,
                            offset: offset,
                            callResult: callResult,
                            location: location
                        )
                        continue
                    }
                    if arguments.count == 2, allocExprs.contains(arguments[0]) {
                        if mustExecute {
                            // Keep the call so the constructor body (init
                            // blocks, parameter checks) still runs; then
                            // overwrite the box result with the raw payload
                            // so downstream code sees the unboxed repr.
                            result.append(instruction)
                            resultLocations.append(location)
                        }
                        // A value-class constructor stores its argument as
                        // the underlying payload. If that payload is itself
                        // a nullable-representation value class crossing an
                        // erased/reference field boundary, retain its nominal
                        // identity inside the new value class.
                        let sourceKind = arena.exprType(arguments[1]).map { types.kind(of: $0) }
                        let underlyingType = symbols.parentSymbol(for: ctorSymbol)
                            .flatMap { symbols.effectiveValueClassUnderlyingType(for: $0) }
                        if let sourceClassSymbol = nullableUnderlyingValueClassSymbol(
                            of: sourceKind, types: types, symbols: symbols
                        ), let underlyingType,
                           valueClassBoxTargetIsBoxed(types.kind(of: underlyingType), symbols: symbols)
                        {
                            var payloadBoxInstructions: [KIRInstruction] = []
                            emitValueClassBoxCall(
                                value: arguments[1], classSymbol: sourceClassSymbol,
                                result: callResult,
                                types: types, symbols: symbols, interner: interner,
                                arena: arena, into: &payloadBoxInstructions
                            )
                            result.append(contentsOf: payloadBoxInstructions)
                            resultLocations.append(contentsOf: repeatElement(location, count: payloadBoxInstructions.count))
                            module.markRawValueClassPayload(callResult)
                        } else {
                            result.append(.copy(from: arguments[1], to: callResult))
                            resultLocations.append(location)
                        }
                        continue
                    } else if arguments.count == 1,
                              allocExprs.contains(arguments[0]),
                              let offset = ctorUnderlyingFieldOffset[ctorSymbol]
                    {
                        if secondaryValueClassCtors.contains(ctorSymbol),
                           let owner = symbols.parentSymbol(for: ctorSymbol),
                           symbols.effectiveValueClassUnderlyingType(for: owner) != nil
                        {
                            result.append(.call(
                                symbol: symbol,
                                callee: callee,
                                arguments: arguments,
                                result: nil,
                                canThrow: canThrow,
                                thrownResult: thrownResult,
                                isSuperCall: isSuperCall,
                                qualifiedSuperType: qualifiedSuperType
                            ))
                            resultLocations.append(location)
                            _ = appendSecondaryValueClassResultExtraction(
                                boxedReceiver: arguments[0],
                                ctorSymbol: ctorSymbol,
                                offset: offset,
                                callResult: callResult,
                                location: location
                            )
                            continue
                        }
                        // Receiver-only construction (e.g. a `V()` default-arg
                        // call): the payload is stored by the constructor
                        // body itself, so keep the call and read the field
                        // back out of the box.
                        result.append(instruction)
                        resultLocations.append(location)
                        let offsetExpr = arena.appendExpr(.intLiteral(offset), type: nil)
                        result.append(.constValue(result: offsetExpr, value: .intLiteral(offset)))
                        resultLocations.append(location)
                        result.append(.call(callee: kk_array_get_inbounds, arguments: [callResult, offsetExpr], result: callResult, canThrow: false))
                        resultLocations.append(location)
                        continue
                    } else if arguments.count == 1, mustExecute,
                              allocExprs.contains(arguments[0])
                    {
                        // Field offset unknown, but the body must still run —
                        // keep the call; its result stays the `this` box and
                        // `kk_unbox_*` reads resolve the stored field.
                        result.append(instruction)
                        resultLocations.append(location)
                        continue
                    } else if arguments.count == 1 {
                        // No explicit receiver
                        result.append(.copy(from: arguments[0], to: callResult))
                        resultLocations.append(location)
                        continue
                    }
                }
                // call kk_array_get_inbounds(receiver, offset) -> result
                if callee == kk_array_get_inbounds,
                   let callResult,
                   arguments.count == 2,
                   !isExecutingCtorThisExpr(
                       arguments[0], arena: arena, symbols: executingCtorThisSymbols
                   ),
                   isValueClassExpr(
                       arguments[0], arena: arena, types: types, symbols: symbols,
                       valueClassSymbols: valueClassSymbols,
                       allowTypeParameterUpperBound: true
                   ),
                   !isNullableUnderlyingValueClassReceiver(
                       arguments[0], arena: arena, types: types, symbols: symbols
                   )
                {
                    if let receiverType = arena.exprType(arguments[0]),
                       let classSymbol = nullableUnderlyingValueClassSymbol(
                           of: types.kind(of: receiverType), types: types, symbols: symbols
                       )
                    {
                        // A non-null nullable-underlying value class already
                        // carries its payload directly. Keep that payload's
                        // underlying type visible to ABI lowering: a plain
                        // copy from the value-class-typed receiver would look
                        // like V -> Any and re-box the payload as V.
                        let classID = module.isRawValueClassPayload(arguments[0])
                            ? 0
                            : RuntimeTypeCheckToken.stableNominalTypeID(
                                symbol: classSymbol, symbols: symbols, interner: interner
                            )
                        let classIDExpr = arena.appendExpr(
                            .intLiteral(classID), type: types.intType
                        )
                        result.append(.constValue(
                            result: classIDExpr, value: .intLiteral(classID)
                        ))
                        resultLocations.append(location)
                        result.append(.call(
                            callee: interner.intern("kk_value_class_unbox"),
                            arguments: [arguments[0], classIDExpr],
                            result: callResult,
                            canThrow: false
                        ))
                    } else if let unboxCallee = valueClassPayloadUnboxCallee(
                        for: arguments[0], arena: arena, types: types, symbols: symbols,
                        valueClassSymbols: valueClassSymbols,
                        boxingCalleeTable: boxingCalleeTable
                    ) {
                        result.append(.call(
                            symbol: nil, callee: unboxCallee, arguments: [arguments[0]],
                            result: callResult, canThrow: false, thrownResult: nil
                        ))
                    } else {
                        // A non-null value class whose underlying representation can
                        // itself be null already stores the raw payload. Preserve this
                        // property read as a representation-only copy; ABI lowering
                        // would otherwise mistake X -> Any? for boxing X itself.
                        if let receiverType = arena.exprType(arguments[0]),
                           let classSymbol = nullableUnderlyingValueClassSymbol(
                               of: types.kind(of: receiverType), types: types, symbols: symbols
                           ),
                           symbols.effectiveValueClassUnderlyingType(for: classSymbol)
                               == arena.exprType(callResult)
                        {
                            module.markRawValueClassPayload(callResult)
                        } else if let receiverType = arena.exprType(arguments[0]),
                                  let classSymbol = referenceBackedValueClassSymbol(
                                      of: types.kind(of: receiverType), types: types, symbols: symbols
                                  ),
                                  case let .classType(classType) = types.kind(of: receiverType),
                                  let declaredUnderlyingType = symbols.effectiveValueClassUnderlyingType(
                                      for: classSymbol
                                  )
                        {
                            // A reference-backed value class's non-null representation is
                            // already its payload. Keep an underlying-property read raw;
                            // otherwise ABI lowering reboxes the payload as the class.
                            let underlyingType = types.substituteNominalTypeParameters(
                                in: declaredUnderlyingType,
                                owner: classSymbol,
                                ownerArgs: classType.args
                            )
                            if underlyingType == arena.exprType(callResult) {
                                module.markRawValueClassPayload(callResult)
                            }
                        }
                        result.append(.copy(from: arguments[0], to: callResult))
                    }
                    resultLocations.append(location)
                    continue
                }
                // Remove auxiliary calls that consume the removed value-class
                // allocation (e.g. kk_object_register_any_to_string): the
                // unboxed value has no heap object to register.
                if let objectArg = arguments.first,
                   allocExprs.contains(objectArg),
                   !keptAllocExprs.contains(objectArg)
                {
                    result.append(.nop)
                    resultLocations.append(location)
                    continue
                }
                result.append(.call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: callResult,
                    canThrow: canThrow,
                    thrownResult: thrownResult,
                    isSuperCall: isSuperCall,
                    qualifiedSuperType: qualifiedSuperType
                ))
                resultLocations.append(location)

            default:
                result.append(instruction)
                resultLocations.append(location)
            }
        }

        return (result, resultLocations)
    }

    /// Inside a constructor that still executes, `this` remains a heap box —
    /// a field read on it must keep the real `kk_array_get_inbounds` call
    /// instead of degenerating to a copy of the box pointer.
    private func isExecutingCtorThisExpr(
        _ expr: KIRExprID,
        arena: KIRArena,
        symbols: Set<SymbolID>
    ) -> Bool {
        guard !symbols.isEmpty,
              case let .symbolRef(symbol) = arena.expr(expr)
        else { return false }
        return symbols.contains(symbol)
    }
}

private extension KIRInstruction {
    /// Whether this instruction is part of a pure field-initialisation
    /// prologue: constants, the underlying-field store, and the return of
    /// `this`. Anything else (init blocks, parameter validation, delegation)
    /// is observable work the constructor must keep executing.
    func isPureValueClassFieldInit(
        kk_array_set: InternedString
    ) -> Bool {
        switch self {
        case .constValue, .nop, .beginBlock, .endBlock,
             .returnValue, .returnUnit:
            return true
        case let .call(_, callee, _, _, _, _, _, _):
            return callee == kk_array_set
        default:
            return false
        }
    }
}
