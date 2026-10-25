final class ObjectLiteralLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func lowerObjectLiteralExpr(
        _ exprID: ExprID,
        superTypes: [TypeRefID],
        declID: DeclID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let objectValueType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        if let declID,
           let decl = ast.arena.decl(declID),
           case let .objectDecl(objectDecl) = decl,
           case let .classType(classType) = sema.types.kind(of: objectValueType)
        {
            return lowerStoredObjectLiteralExpr(
                exprID,
                objectDecl: objectDecl,
                objectSymbol: classType.classSymbol,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        let symbols = syntheticObjectLiteralSymbols(for: exprID, interner: interner)
        ensureObjectLiteralGeneratedDecls(
            exprID: exprID,
            superTypeCount: superTypes.count,
            objectValueType: objectValueType,
            symbols: symbols,
            sema: sema,
            arena: arena,
            interner: interner
        )

        let objectValue = arena.appendTemporary(type: objectValueType)
        instructions.append(.call(
            symbol: symbols.constructorSymbol,
            callee: symbols.constructorName,
            arguments: [],
            result: objectValue,
            canThrow: false
        ))
        return objectValue
    }

    /// A local `object` materializes its singleton right at the declaration
    /// site (exactly like an object literal) and binds it to the declared
    /// name's symbol; a local `class` only emits its nominal/member/`<init>`
    /// declarations — instances come from later `Local(...)` call exprs,
    /// which take the normal constructor-call path in `CallLowerer`.
    func lowerLocalNominalDeclExpr(
        _ exprID: ExprID,
        declID: DeclID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let unitExpr = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unitExpr, value: .unit))
        guard let decl = ast.arena.decl(declID),
              let ownerSymbol = sema.bindings.declSymbols[declID]
        else {
            return unitExpr
        }
        switch decl {
        case let .objectDecl(objectDecl):
            // Nested member/accessor function emissions reset the scope
            // (`resetScopeForFunction`) while lowering their own bodies —
            // restore the enclosing scope afterwards so this decl's own
            // instance binding and any outer locals it captures survive.
            let nominalScopeSnapshot = driver.ctx.saveScope()
            let objectValue = lowerStoredObjectLiteralExpr(
                    exprID,
                    objectDecl: objectDecl,
                    objectSymbol: ownerSymbol,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            driver.ctx.restoreScope(nominalScopeSnapshot)
            // `Local` references lower as locals — bind the symbol to the
            // materialized singleton value.
            driver.ctx.setLocalValue(objectValue, for: ownerSymbol)

        case let .classDecl(classDecl):
            // Same scope protection as the object path: member and
            // constructor body emissions below reset the scope.
            let nominalScopeSnapshot = driver.ctx.saveScope()
            defer { driver.ctx.restoreScope(nominalScopeSnapshot) }
            guard ensureObjectLiteralNominalDecl(
                exprID: exprID,
                objectSymbol: ownerSymbol,
                arena: arena
            ) else {
                break
            }
            let ownerFQName = sema.symbols.symbol(ownerSymbol)?.fqName ?? []
            if !classDecl.memberFunctions.isEmpty
                || !classDecl.nestedClasses.isEmpty
                || !classDecl.nestedObjects.isEmpty
            {
                let (_, allDecls) = driver.memberLowerer.lowerMemberDecls(
                    memberFunctions: classDecl.memberFunctions,
                    memberProperties: [],
                    nestedClasses: classDecl.nestedClasses,
                    nestedObjects: classDecl.nestedObjects,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers
                )
                for memberDeclID in allDecls {
                    driver.ctx.appendGeneratedCallableDecl(memberDeclID)
                }
            }
            lowerObjectLiteralPropertyAccessors(
                classDecl.memberProperties,
                ownerFQName: ownerFQName,
                objectSymbol: ownerSymbol,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
            let shared = KIRLoweringSharedContext(
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
            let forwardingDecls = driver.synthesizeClassDelegationForwardingMethods(
                classSymbol: ownerSymbol, shared: shared, compilationCtx: nil
            ) + driver.synthesizeClassDelegationForwardingPropertyAccessors(
                classSymbol: ownerSymbol, shared: shared, compilationCtx: nil
            )
            for forwardingDeclID in forwardingDecls {
                driver.ctx.appendGeneratedCallableDecl(forwardingDeclID)
            }
            let initName = interner.intern("<init>")
            let ctorFQName = ownerFQName + [initName]
            for ctorSymbol in sema.symbols.lookupAll(fqName: ctorFQName).filter({
                sema.symbols.symbol($0)?.kind == .constructor
            }) {
                let ctorDecls = driver.lowerConstructor(
                    ctorSymbol: ctorSymbol,
                    ctorFQName: ctorFQName,
                    classDecl: classDecl,
                    ownerSymbol: ownerSymbol,
                    shared: KIRLoweringSharedContext(
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers
                    )
                )
                for ctorDeclID in ctorDecls {
                    driver.ctx.appendGeneratedCallableDecl(ctorDeclID)
                }
            }

        default:
            break
        }
        return unitExpr
    }

    private func lowerStoredObjectLiteralExpr(
        _ exprID: ExprID,
        objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let objectValueType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let emittedNominal = ensureObjectLiteralNominalDecl(exprID: exprID, objectSymbol: objectSymbol, arena: arena)
        if emittedNominal {
            let scopeSnapshot = driver.ctx.saveScope()
            defer { driver.ctx.restoreScope(scopeSnapshot) }
            lowerObjectLiteralNestedMembers(
                objectDecl,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
            lowerObjectLiteralMemberFunctions(
                objectDecl,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
            // BUG-141: object-literal member properties are not lowered through
            // MemberLowerer above (memberProperties: []), so synthesize a getter
            // accessor for each property that overrides an interface property.
            // appendObjectItableMethodRegistrations registers these getters into
            // the interface itable so an interface-typed receiver can read them.
            lowerObjectLiteralPropertyAccessors(
                objectDecl.memberProperties,
                ownerFQName: sema.symbols.symbol(objectSymbol)?.fqName ?? [objectDecl.name],
                objectSymbol: objectSymbol,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
            let shared = KIRLoweringSharedContext(
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
            let forwardingDecls = driver.synthesizeClassDelegationForwardingMethods(
                classSymbol: objectSymbol, shared: shared, compilationCtx: nil
            ) + driver.synthesizeClassDelegationForwardingPropertyAccessors(
                classSymbol: objectSymbol, shared: shared, compilationCtx: nil
            )
            for declID in forwardingDecls {
                driver.ctx.appendGeneratedCallableDecl(declID)
            }
        }

        let intType = sema.types.intType
        let layout = sema.symbols.nominalLayout(for: objectSymbol)
        let slotCount = Int64(max(layout?.instanceSizeWords ?? 1, 1))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: objectSymbol,
            sema: sema,
            interner: interner
        )

        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))

        let objectValue = arena.appendTemporary(type: objectValueType)
        instructions.append(.call(
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: objectValue,
            canThrow: false
        ))

        registerObjectLiteralSupertypes(
            objectSymbol: objectSymbol,
            objectValue: objectValue,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        appendObjectItableMethodRegistrations(
            objectValue: objectValue,
            nominalSymbol: objectSymbol,
            driver: driver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        appendObjectVtableMethodRegistrations(
            objectValue: objectValue,
            nominalSymbol: objectSymbol,
            driver: driver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        appendObjectAnyToStringRegistration(
            objectValue: objectValue,
            nominalSymbol: objectSymbol,
            driver: driver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        // Seed `lateinit` fields with the null sentinel before the
        // superclass constructor runs (a fresh object's fields are 0, which
        // the lateinit read path would take for a live value).
        let lateinitSentinelSymbols = driver.lateinitSentinelPropertySymbols(
            objectDecl.memberProperties,
            shared: KIRLoweringSharedContext(
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
        )
        for propertySymbol in lateinitSentinelSymbols {
            let targetSymbol = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            guard let fieldOffset = layout?.fieldOffsets[targetSymbol] else { continue }
            let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
            let nullExpr = arena.appendExpr(.null, type: propertyType)
            instructions.append(.constValue(result: nullExpr, value: .null))
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let unusedResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                callee: interner.intern("kk_array_set"),
                arguments: [objectValue, offsetExpr, nullExpr],
                result: unusedResult,
                canThrow: false
            ))
        }
        // KSP-CAP-001: materialize outer locals/parameters and any enclosing
        // receiver captured by this object's member functions into instance fields, while the
        // *enclosing* function's implicit receiver and locals are still
        // active (needed so `captureValueExpr` can resolve a captured outer
        // `this` correctly) -- i.e. before `setImplicitReceiver` below
        // switches the active receiver over to this object literal itself.
        // Runs before the superclass constructor call because a local
        // superclass's `<init>` restores its own captures from these fields.
        let capturedSymbols = sema.bindings.objectLiteralCaptureSymbols(for: objectSymbol)
        for capturedSymbol in capturedSymbols {
            guard let fieldOffset = layout?.fieldOffsets[capturedSymbol],
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
            instructions.append(.constValue(result: captureOffsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let captureSetResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                callee: interner.intern("kk_array_set"),
                arguments: [objectValue, captureOffsetExpr, captureValue],
                result: captureSetResult,
                canThrow: true
            ))
        }

        emitObjectLiteralSuperConstructorCall(
            objectDecl,
            objectSymbol: objectSymbol,
            objectValue: objectValue,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        // Initialize each delegate once in header order while the enclosing
        // receiver is still active, before any property or init block can call it.
        var delegationBody = KIRLoweringEmitContext(instructions)
        driver.emitClassDelegationInitializers(
            ownerSymbol: objectSymbol,
            receiverID: objectValue,
            superTypeEntries: objectDecl.superTypeEntries,
            shared: KIRLoweringSharedContext(
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            ),
            body: &delegationBody
        )
        instructions = delegationBody.instructions

        let initializerScopeSnapshot = driver.ctx.saveScope()
        let savedReceiverExprID = driver.ctx.activeImplicitReceiverExprID()
        if let savedReceiverExprID,
           let receiverType = arena.exprType(savedReceiverExprID),
           let receiverLabel = RuntimeTypeCheckToken.simpleName(
               of: receiverType,
               sema: sema,
               interner: interner
           )
        {
            driver.ctx.setQualifiedThisReceiver(
                savedReceiverExprID,
                for: interner.intern(receiverLabel)
            )
        }
        // KUU-2111: property initializers execute with the new object as the
        // active receiver, but an unqualified member read can still belong to
        // the enclosing class. Keep the construction-site receiver available
        // during this inline initializer pass so field offsets are applied to
        // the enclosing instance instead of the not-yet-initialized object.
        if let savedReceiverExprID,
           let receiverType = arena.exprType(savedReceiverExprID),
           case let .classType(receiverClass) = sema.types.kind(
               of: sema.types.makeNonNullable(receiverType)
           )
        {
            driver.ctx.setCapturedOuterReceiver(savedReceiverExprID, for: receiverClass.classSymbol)
        }
        driver.ctx.setImplicitReceiver(symbol: objectSymbol, exprID: objectValue)
        defer { driver.ctx.restoreScope(initializerScopeSnapshot) }

        // Property initializers and `init {}` blocks run interleaved in
        // declaration order. An object decl without a recorded order (no
        // `init` blocks were ever collected for it) keeps running its
        // properties in member order.
        let initOrder = objectDecl.classBodyInitOrder.isEmpty
            ? objectDecl.memberProperties.indices.map { ClassBodyInitMember.property($0) }
            : objectDecl.classBodyInitOrder
        for member in initOrder {
            let propertyDeclID: DeclID
            switch member {
            case let .initBlock(index):
                guard index < objectDecl.initBlocks.count else { continue }
                let initBlockExprs: [ExprID] = switch objectDecl.initBlocks[index] {
                case let .block(exprIDs, _): exprIDs
                case let .expr(exprID, _): [exprID]
                case .unit: []
                }
                for exprID in initBlockExprs {
                    _ = driver.lowerExpr(
                        exprID,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                }
                continue
            case let .property(index):
                guard index < objectDecl.memberProperties.count else { continue }
                propertyDeclID = objectDecl.memberProperties[index]
            }
            guard let propertySymbol = sema.bindings.declSymbols[propertyDeclID],
                  let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            if propertyDecl.delegateExpression != nil {
                // BUG-267: run the same delegate-expression initialization a
                // named class performs in its constructor, storing the
                // delegate instance into the object's `$delegate_<name>`
                // field. The object literal is the active implicit receiver
                // here, so `emitFieldStore` lands at the layout offset.
                _ = objectLiteralDelegateStorageSymbol(
                    for: propertySymbol,
                    propertyDecl: propertyDecl,
                    ownerFQName: sema.symbols.symbol(objectSymbol)?.fqName ?? [objectDecl.name],
                    objectSymbol: objectSymbol,
                    sema: sema,
                    interner: interner
                )
                var emitContext = KIRLoweringEmitContext(instructions)
                driver.emitDelegatePropertyInitializer(
                    propertyDecl: propertyDecl,
                    propSymbol: propertySymbol,
                    sema: sema,
                    arena: arena,
                    shared: KIRLoweringSharedContext(
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers
                    ),
                    body: &emitContext
                )
                instructions = emitContext.instructions
                continue
            }
            guard let initializer = propertyDecl.initializer,
                  let fieldOffset = layout?.fieldOffsets[sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol]
            else {
                continue
            }
            let initializerValue = driver.lowerExpr(
                initializer,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let unusedResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                callee: interner.intern("kk_array_set"),
                arguments: [objectValue, offsetExpr, initializerValue],
                result: unusedResult,
                canThrow: true
            ))
        }

        return objectValue
    }

    /// KSP-CAP-018: Kotlin runs the superclass constructor before the object
    /// literal's own initializers, so the superclass's property initializers
    /// and `init` blocks — which write into the same instance at the layout
    /// offsets the object literal inherits — must execute here. Without this
    /// call an object literal instance keeps the zeroed defaults for every
    /// inherited property (same root cause as BUG-155/PR #5506's
    /// `emitSuperConstructorDelegation` for named classes; object literals
    /// never went through that fix since they have no user-written
    /// constructor of their own).
    private func emitObjectLiteralSuperConstructorCall(
        _ objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        objectValue: KIRExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) {
        guard let superclassSymbol = sema.symbols.directSupertypes(for: objectSymbol).first(where: {
            let kind = sema.symbols.symbol($0)?.kind
            return kind == .class || kind == .enumClass
        }),
        let superclassInfo = sema.symbols.symbol(superclassSymbol)
        else {
            return
        }
        // An anonymous subclass reuses its inner superclass's `$outer` slot.
        // The object itself is already allocated, so initialize that inherited
        // link from the active receiver before the superclass constructor (or
        // its argument expressions) can read members from the enclosing owner.
        storeOuterInstanceLinkIfNeeded(
            allocatedObject: objectValue,
            innerClassSymbol: superclassSymbol,
            outerReceiver: driver.ctx.activeImplicitReceiverExprID(),
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let candidates = sema.symbols.lookupAll(fqName: superclassInfo.fqName + [interner.intern("<init>")])
        let callBinding = sema.bindings.constructorDelegationCallBinding(for: objectSymbol)
        guard let superCtorSymbol = callBinding?.chosenCallee ?? driver.resolveObjectSuperConstructor(
            candidates: candidates,
            argExprs: objectDecl.superTypeConstructorArgs.map(\.expr),
            sema: sema
        )
        else {
            return
        }
        // Source-backed constructors — bundled stdlib or imported .kklib
        // declarations — carry a linkable external body, so their non-empty
        // externalLinkName must not suppress the call (the same rule
        // emitSuperConstructorDelegation applies for named classes). Only
        // synthetic shells with no real body and runtime factory constructors
        // (whose ABI returns a fresh box instead of initializing `this`) are
        // skipped.
        guard !(sema.symbols.symbol(superCtorSymbol)?.flags.contains(.synthetic) ?? false)
            || sema.symbols.isSourceBackedSymbol(superCtorSymbol),
            !driver.callLowerer.isRuntimeFactoryConstructor(superCtorSymbol, sema: sema)
        else {
            return
        }
        if sema.symbols.symbol(superCtorSymbol)?.flags.contains(.synthetic) == true,
           sema.symbols.parentSymbol(for: superCtorSymbol) == sema.types.anyClassSymbol
        {
            // Any's compiler-provided constructor has no body to delegate to.
            return
        }

        var loweredArgs: [KIRExprID] = []
        for arg in objectDecl.superTypeConstructorArgs {
            loweredArgs.append(driver.lowerExpr(
                arg.expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            ))
        }

        // `object : Outer.Inner()` inherits the inner superclass's `$outer`
        // field — write it while the enclosing receiver is still active so
        // inherited members can walk the outer chain (KUU-2959).
        storeInheritedOuterInstanceLinks(
            allocatedObject: objectValue,
            constructedClassSymbol: objectSymbol,
            outerReceiver: driver.ctx.activeImplicitReceiverExprID(),
            driver: driver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        let resultID = arena.appendTemporary(type: sema.types.unitType)
        var body = KIRLoweringEmitContext(instructions)
        driver.emitDelegatedConstructorCall(
            target: superCtorSymbol,
            receiver: objectValue,
            loweredArgs: loweredArgs,
            spreadFlags: objectDecl.superTypeConstructorArgs.map(\.isSpread),
            argumentLabels: objectDecl.superTypeConstructorArgs.map(\.label),
            callBinding: callBinding,
            sourceArgExprs: objectDecl.superTypeConstructorArgs.map(\.expr),
            result: resultID,
            shared: KIRLoweringSharedContext(
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            ),
            body: &body
        )
        instructions = body.instructions
    }

    /// KSP-CAP-001: member functions are lowered as independent top-level KIR
    /// functions (`MemberLowerer.lowerSingleMemberFunction` resets `driver.ctx`'s
    /// scope per function, the same way `LambdaLowerer` does per lambda), so
    /// a captured symbol's KIR value from the enclosing function is not
    /// visible here on its own, so the capture must be read back from the
    /// instance field it was stored into at construction time (see the capture
    /// loop in `lowerStoredObjectLiteralExpr` above), then re-registered with
    /// `driver.ctx` so ordinary `nameRef` lowering finds it exactly as if it
    /// were a plain local.
    func restoreObjectLiteralCaptures(
        forMemberFunction functionSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard let ownerSymbol = sema.symbols.parentSymbol(for: functionSymbol) else {
            return
        }
        let capturedSymbols = sema.bindings.objectLiteralCaptureSymbols(for: ownerSymbol)
        // Member extensions keep their extension receiver active, but captures live on the object instance.
        guard !capturedSymbols.isEmpty,
              let receiverExprID = driver.ctx.localValue(for: ownerSymbol)
                  ?? driver.ctx.activeImplicitReceiverExprID(),
              let layout = sema.symbols.nominalLayout(for: ownerSymbol)
        else {
            return
        }

        let intType = sema.types.intType
        for capturedSymbol in capturedSymbols {
            guard let fieldOffset = layout.fieldOffsets[capturedSymbol] else {
                continue
            }
            let isMutableLocal = sema.symbols.symbol(capturedSymbol).map {
                $0.kind == .local && $0.flags.contains(.mutable)
            } ?? false
            let isReifiedTypeParameter = sema.symbols.symbol(capturedSymbol).map {
                $0.kind == .typeParameter && $0.flags.contains(.reifiedTypeParameter)
            } ?? false
            // A delegated local (`var x by Prop()`/`val x by lazy {}`) stores
            // its delegate *instance* in the capture field, not a boxed cell
            // and not the property value — exactly what `captureValueExpr`
            // materialized and what `bindCapturedLambdaValue` restores for
            // lambdas. Mutable captures hold boxed cells, and reified
            // captures hold a pair of raw tokens. Keep all three generic
            // until they are unwrapped; ordinary immutable captures can use
            // their logical type directly.
            let isDelegatedLocal = sema.symbols.delegateGetValueSymbol(for: capturedSymbol) != nil
            let logicalType = sema.bindings.capturedLocalType(for: capturedSymbol)
                ?? driver.lambdaLowerer.typeForSymbolReference(capturedSymbol, sema: sema)
            let loadedType = isMutableLocal || isDelegatedLocal || isReifiedTypeParameter
                ? sema.types.anyType
                : logicalType

            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let loadedExpr = arena.appendTemporary(type: loadedType)
            instructions.append(.call(
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverExprID, offsetExpr],
                result: loadedExpr,
                canThrow: false
            ))
            if isDelegatedLocal {
                driver.ctx.setLocalDelegateStorage(loadedExpr, for: capturedSymbol)
            } else if isMutableLocal {
                driver.ctx.setMutableCaptureCell(loadedExpr, for: capturedSymbol)
            } else {
                driver.ctx.setLocalValue(loadedExpr, for: capturedSymbol)
            }
            driver.ctx.setLocalDeclaredType(logicalType, for: capturedSymbol)
            if isReifiedTypeParameter {
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: capturedSymbol)
                let componentSymbol = SyntheticSymbolScheme.reifiedArrayComponentTokenSymbol(for: capturedSymbol)
                let classToken = arena.appendTemporary(type: intType)
                instructions.append(.call(callee: interner.intern("__kk_pair_first"), arguments: [loadedExpr], result: classToken, canThrow: false))
                let componentToken = arena.appendTemporary(type: intType)
                instructions.append(.call(
                    callee: interner.intern("__kk_pair_second"),
                    arguments: [loadedExpr],
                    result: componentToken,
                    canThrow: false
                ))
                driver.ctx.setLocalValue(classToken, for: tokenSymbol)
                driver.ctx.setLocalDeclaredType(intType, for: tokenSymbol)
                driver.ctx.setLocalValue(componentToken, for: componentSymbol)
                driver.ctx.setLocalDeclaredType(intType, for: componentSymbol)
            }
            if let capturedOwner = sema.symbols.symbol(capturedSymbol),
               [.class, .interface, .enumClass, .object].contains(capturedOwner.kind)
            {
                driver.ctx.setCapturedOuterReceiver(loadedExpr, for: capturedSymbol)
                driver.ctx.setQualifiedThisReceiver(loadedExpr, for: capturedOwner.name)
            }
            if let capturedReceiver = sema.bindings.objectLiteralCapturedReceiver(for: ownerSymbol),
               capturedReceiver.receiverSymbol == capturedSymbol
            {
                driver.ctx.setCapturedOuterReceiver(loadedExpr, for: capturedReceiver.ownerSymbol)
            }
        }
    }

    func implicitReceiverExprID(
        forProperty symbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena
    ) -> KIRExprID? {
        // `field` is bound to its backing-field symbol, but its receiver is
        // the instance whose getter owns that field. Prefer the captured owner
        // value so a nested lambda's same-typed implicit receiver cannot
        // redirect the read to another instance.
        if sema.symbols.symbol(symbol)?.kind == .backingField,
           let owner = sema.symbols.parentSymbol(for: symbol),
           let receiver = driver.ctx.localValue(for: owner)
        {
            return receiver
        }

        // Once an object literal starts initializing its own properties, the
        // active receiver value is the object, even though the enclosing
        // function signature may still have an extension receiver type.
        let activeReceiverType = driver.ctx.activeImplicitReceiver().flatMap { receiver in
            driver.ctx.localDeclaredType(for: receiver.symbol) ?? arena.exprType(receiver.exprID)
        } ?? driver.ctx.currentFunctionSymbol.flatMap {
            sema.symbols.functionSignature(for: $0)?.receiverType
        }
        // An extension property's bare reference uses the extension receiver;
        // the enclosing instance is a separate leading accessor argument.
        if let extensionType = sema.symbols.extensionPropertyReceiverType(for: symbol),
           let activeReceiver = driver.ctx.activeImplicitReceiverExprID(),
           let receiverType = activeReceiverType,
           sema.types.isSubtype(
               sema.types.makeNonNullable(receiverType),
               sema.types.makeNonNullable(extensionType)
           )
        {
            return activeReceiver
        }
        if let owner = sema.symbols.parentSymbol(for: symbol),
           let activeReceiver = driver.ctx.activeImplicitReceiverExprID(),
           let receiverType = activeReceiverType,
           case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
           sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: owner)
        {
            return activeReceiver
        }
        if let owner = sema.symbols.parentSymbol(for: symbol),
           let receiver = driver.ctx.capturedOuterReceiverExprID(for: owner)
               ?? driver.ctx.capturedOuterReceiverExprID(reaching: owner, sema: sema)
        {
            return receiver
        }
        guard let propertyOwner = sema.symbols.parentSymbol(for: symbol),
              let functionSymbol = driver.ctx.currentFunctionSymbol,
              let objectOwner = sema.symbols.parentSymbol(for: functionSymbol),
              let capturedReceiver = sema.bindings.objectLiteralCapturedReceiver(for: objectOwner)
        else {
            return driver.ctx.activeImplicitReceiverExprID()
        }
        var visited: Set<SymbolID> = []
        var pending = [capturedReceiver.ownerSymbol]
        while let owner = pending.popLast() {
            guard visited.insert(owner).inserted else { continue }
            if owner == propertyOwner,
               let receiverExprID = driver.ctx.capturedOuterReceiverExprID(for: capturedReceiver.ownerSymbol)
            {
                return receiverExprID
            }
            pending.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        return driver.ctx.activeImplicitReceiverExprID()
    }

    private func registerObjectLiteralSupertypes(
        objectSymbol: SymbolID,
        objectValue _: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let childTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: objectSymbol,
            sema: sema,
            interner: interner
        )
        appendNominalSupertypeEdgeRegistrations(
            childSymbol: objectSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        registerKClassMetadata(
            objectSymbol: objectSymbol,
            typeID: childTypeID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    private func registerKClassMetadata(
        objectSymbol: SymbolID,
        typeID: Int64,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard let symbol = sema.symbols.symbol(objectSymbol) else { return }

        let intType = sema.types.intType

        let typeToken = RuntimeTypeCheckToken.encode(
            base: RuntimeTypeCheckToken.nominalBase,
            nullable: false,
            payload: typeID
        )
        let typeTokenExpr = arena.appendExpr(.intLiteral(typeToken), type: intType)
        instructions.append(.constValue(result: typeTokenExpr, value: .intLiteral(typeToken)))

        let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
        let fqNameInterned = interner.intern(fqName)
        let fqNameExpr = arena.appendExpr(.stringLiteral(fqNameInterned), type: intType)
        instructions.append(.constValue(result: fqNameExpr, value: .stringLiteral(fqNameInterned)))

        let simpleName = interner.resolve(symbol.name)
        let simpleNameInterned = interner.intern(simpleName)
        let simpleNameExpr = arena.appendExpr(.stringLiteral(simpleNameInterned), type: intType)
        instructions.append(.constValue(result: simpleNameExpr, value: .stringLiteral(simpleNameInterned)))

        // Supertype display names ('|'-joined, KUU-1357).
        let supertypeNameExpr: KIRExprID
        if let joined = kclassSupertypeDisplayNamesJoined(
            for: objectSymbol, sema: sema, interner: interner
        ) {
            let superInterned = interner.intern(joined)
            supertypeNameExpr = arena.appendExpr(.stringLiteral(superInterned), type: intType)
            instructions.append(.constValue(result: supertypeNameExpr, value: .stringLiteral(superInterned)))
        } else {
            supertypeNameExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: supertypeNameExpr, value: .intLiteral(0)))
        }

        // Flags: bit 0=dataClass, bit 1=sealedClass, bit 2=valueClass,
        //        bit 3=interface, bit 4=object, bit 5=enumClass,
        //        bit 6=annotationClass, bit 7=abstract,
        //        bit 10=inner, bit 11=companion, bit 12=funInterface. (STDLIB-REFLECT-067)
        var flags: Int64 = 0
        if symbol.flags.contains(.dataType) { flags |= 1 << 0 }
        if symbol.flags.contains(.sealedType) { flags |= 1 << 1 }
        if symbol.flags.contains(.valueType) { flags |= 1 << 2 }
        if symbol.kind == .interface { flags |= 1 << 3 }
        if symbol.kind == .object { flags |= 1 << 4 }
        if symbol.kind == .enumClass { flags |= 1 << 5 }
        if symbol.kind == .annotationClass { flags |= 1 << 6 }
        // Reflection reports Kotlin modality, not the internal inheritance flags.
        let isSealed = symbol.flags.contains(.sealedType)
        let isAbstract = !isSealed && (symbol.kind == .interface || symbol.kind == .annotationClass || symbol.flags.contains(.abstractType))
        if isAbstract { flags |= 1 << 7 }
        if !isSealed && !isAbstract && !symbol.flags.contains(.openType) { flags |= 1 << 8 }
        if !isSealed && !isAbstract && symbol.flags.contains(.openType) { flags |= 1 << 9 }
        if symbol.flags.contains(.innerClass) { flags |= 1 << 10 }
        if symbol.flags.contains(.funInterface) { flags |= 1 << 12 }
        if symbol.kind == .object {
            let parentFQName = Array(symbol.fqName.dropLast())
            if let parentSymbol = sema.symbols.lookup(fqName: parentFQName),
               sema.symbols.companionObjectSymbol(for: parentSymbol) == objectSymbol {
                flags |= 1 << 11
            }
        }
        let ownerKind = sema.symbols.parentSymbol(for: objectSymbol)
            .flatMap { sema.symbols.symbol($0)?.kind }
        let isLocalOrAnonymous = symbol.fqName.contains { component in
            let name = interner.resolve(component)
            return name.hasPrefix("__localdecl_") || name.hasPrefix("__ObjectLiteral_")
        }
        if isLocalOrAnonymous
            || ownerKind.map({ [.function, .property, .local].contains($0) }) == true
            || (symbol.kind == .object && symbol.flags.contains(.synthetic)) {
            flags |= 1 << 13
        }
        let flagsExpr = arena.appendExpr(.intLiteral(flags), type: intType)
        instructions.append(.constValue(result: flagsExpr, value: .intLiteral(flags)))

        let fieldCount: Int64
        if let layout = sema.symbols.nominalLayout(for: objectSymbol) {
            fieldCount = Int64(layout.instanceFieldCount)
        } else {
            fieldCount = -1
        }
        let fieldCountExpr = arena.appendExpr(.intLiteral(fieldCount), type: intType)
        instructions.append(.constValue(result: fieldCountExpr, value: .intLiteral(fieldCount)))

        let memberCount: Int64
        if let layout = sema.symbols.nominalLayout(for: objectSymbol) {
            memberCount = Int64(layout.instanceFieldCount + layout.vtableSize)
        } else {
            memberCount = -1
        }
        let memberCountExpr = arena.appendExpr(.intLiteral(memberCount), type: intType)
        instructions.append(.constValue(result: memberCountExpr, value: .intLiteral(memberCount)))

        let constructorCount = Int64(sema.symbols.children(ofFQName: symbol.fqName).filter { child in
            sema.symbols.symbol(child)?.kind == .constructor
        }.count)
        let constructorCountExpr = arena.appendExpr(.intLiteral(constructorCount), type: intType)
        instructions.append(.constValue(result: constructorCountExpr, value: .intLiteral(constructorCount)))

        let registerResult = arena.appendTemporary(type: intType)
        instructions.append(.call(
            callee: interner.intern("__kk_kclass_register_metadata"),
            arguments: [typeTokenExpr, fqNameExpr, simpleNameExpr, supertypeNameExpr, flagsExpr, fieldCountExpr, memberCountExpr, constructorCountExpr],
            result: registerResult,
            canThrow: false
        ))
        driver.callLowerer.emitClassEnclosingMetadataRegistration(
            for: objectSymbol,
            typeTokenExpr: typeTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        emitKClassDisplayNameRegistration(
            symbol: objectSymbol, typeTokenExpr: typeTokenExpr,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )
        emitKClassCompanionAndNestedRegistration(
            classSymbol: objectSymbol, typeTokenExpr: typeTokenExpr,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )

        emitKClassAnnotationRegistration(
            objectSymbol: objectSymbol,
            typeTokenExpr: typeTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        // KUU-1448: keep the transitive nominal-supertype closure registered
        // as well — `KType.classifier`-synthesized handles for an ancestor
        // resolve their own `supertypes` through the same registry.
        var visitedClassSymbols: Set<SymbolID> = [objectSymbol]
        driver.callLowerer.emitTransitiveSupertypeKClassMetadataRegistrations(
            for: objectSymbol,
            visitedClassSymbols: &visitedClassSymbols,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    private func ensureObjectLiteralNominalDecl(
        exprID: ExprID,
        objectSymbol: SymbolID,
        arena: KIRArena
    ) -> Bool {
        guard driver.ctx.markObjectLiteralEmitted(exprID) else {
            return false
        }
        let nominalDeclID = arena.appendDecl(.nominalType(KIRNominalType(symbol: objectSymbol)))
        driver.ctx.appendGeneratedCallableDecl(nominalDeclID)
        return true
    }

    private func lowerObjectLiteralMemberFunctions(
        _ objectDecl: ObjectDecl,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) {
        guard !objectDecl.memberFunctions.isEmpty else {
            return
        }
        let (_, allDecls) = driver.memberLowerer.lowerMemberDecls(
            memberFunctions: objectDecl.memberFunctions,
            memberProperties: [],
            nestedClasses: [],
            nestedObjects: [],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
        for declID in allDecls {
            driver.ctx.appendGeneratedCallableDecl(declID)
        }
    }

    private func lowerObjectLiteralNestedMembers(
        _ objectDecl: ObjectDecl,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) {
        guard !objectDecl.nestedClasses.isEmpty || !objectDecl.nestedObjects.isEmpty else {
            return
        }
        let (_, allDecls) = driver.memberLowerer.lowerMemberDecls(
            memberFunctions: [],
            memberProperties: [],
            nestedClasses: objectDecl.nestedClasses,
            nestedObjects: objectDecl.nestedObjects,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
        for declID in allDecls {
            driver.ctx.appendGeneratedCallableDecl(declID)
        }
    }

    /// BUG-141: emit accessor functions for object-literal member properties
    /// that override an interface property, so they can be dispatched through
    /// the interface itable.
    ///
    /// KSP-CAP-018: also emits the `set` accessor for a property that declares
    /// one. The assignment path already lowered `obj.prop = v` to `call set`,
    /// so a custom setter used to fail at link time with an undefined `_set`.
    private func lowerObjectLiteralPropertyAccessors(
        _ memberProperties: [DeclID],
        ownerFQName: [InternedString],
        objectSymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) {
        guard !memberProperties.isEmpty else {
            return
        }
        var allDecls: [KIRDeclID] = []
        for propertyDeclID in memberProperties {
            guard let propertySymbol = sema.bindings.declSymbols[propertyDeclID],
                  let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
            // BUG-267: delegated properties get their accessors synthesized
            // through the same getValue/setValue convention as named-class
            // members (`MemberLowerer.lowerDelegateAccessor`). Both read
            // paths — explicit `o.x` and implicit reads inside member
            // functions — lower to `call get`/`call set` on this accessor;
            // the delegate instance lives in the object's `$delegate_<name>`
            // field (stored in `lowerStoredObjectLiteralExpr`).
            if let delegateExpr = propertyDecl.delegateExpression {
                let delegateStorageSymbol = objectLiteralDelegateStorageSymbol(
                    for: propertySymbol,
                    propertyDecl: propertyDecl,
                    ownerFQName: ownerFQName,
                    objectSymbol: objectSymbol,
                    sema: sema,
                    interner: interner
                )
                let delegateKind = StdlibDelegateKind.detect(
                    delegateExpr: delegateExpr, ast: ast, interner: interner
                )
                driver.memberLowerer.lowerDelegateAccessor(
                    propertySymbol: propertySymbol,
                    propertyType: propertyType,
                    delegateStorageSymbol: delegateStorageSymbol,
                    delegateKind: delegateKind,
                    accessorKind: .getter,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    allDecls: &allDecls
                )
                if propertyDecl.isVar {
                    driver.memberLowerer.lowerDelegateAccessor(
                        propertySymbol: propertySymbol,
                        propertyType: propertyType,
                        delegateStorageSymbol: delegateStorageSymbol,
                        delegateKind: delegateKind,
                        accessorKind: .setter,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        allDecls: &allDecls
                    )
                }
                continue
            }
            // Every non-delegated property gets a getter accessor, including
            // non-virtual properties used directly by object-literal reads.
            // Dispatch registration wires up the class/interface overrides.
            if let getter = propertyDecl.getter, getter.body != .unit {
                driver.memberLowerer.lowerAccessorBody(
                    accessorBody: getter.body,
                    propertySymbol: propertySymbol,
                    propertyType: propertyType,
                    accessorKind: .getter,
                    setterParamName: nil,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    allDecls: &allDecls
                )
            } else {
                driver.memberLowerer.synthesizeStoredPropertyGetterAccessor(
                    propertySymbol: propertySymbol,
                    ownerSymbol: objectSymbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    allDecls: &allDecls
                )
            }
            if let setter = propertyDecl.setter, setter.body != .unit {
                driver.memberLowerer.lowerAccessorBody(
                    accessorBody: setter.body,
                    propertySymbol: propertySymbol,
                    propertyType: propertyType,
                    accessorKind: .setter,
                    setterParamName: setter.parameterName,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    allDecls: &allDecls
                )
            } else if propertyDecl.isVar {
                // Setter counterpart of the stored getter accessor above: a
                // plain `var` (no custom setter body) still needs a real
                // setter accessor function registered so a write through an
                // interface-typed receiver can dispatch to this object
                // literal's own storage, the same way its getter already does.
                driver.memberLowerer.synthesizeStoredPropertySetterAccessor(
                    propertySymbol: propertySymbol,
                    ownerSymbol: objectSymbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    allDecls: &allDecls
                )
            }
        }
        for declID in allDecls {
            driver.ctx.appendGeneratedCallableDecl(declID)
        }
    }

    /// BUG-267: resolves the `$delegate_<name>` storage symbol Sema registers
    /// for an object-literal delegated property (`ensureObjectLiteralSymbol`).
    /// The fallback define mirrors `MemberLowerer`'s define-on-demand path for
    /// named classes so lowering stays total if the Sema invariant is ever
    /// bypassed (e.g. a synthetic AST built without the full inference pass).
    private func objectLiteralDelegateStorageSymbol(
        for propertySymbol: SymbolID,
        propertyDecl: PropertyDecl,
        ownerFQName: [InternedString],
        objectSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID {
        if let existing = sema.symbols.delegateStorageSymbol(for: propertySymbol) {
            return existing
        }
        let extensionSuffix = sema.symbols.hasExtensionPropertyReceiver(propertySymbol)
            ? "_extension_\(propertySymbol.rawValue)"
            : ""
        let storageName = interner.intern(
            "$delegate_\(interner.resolve(propertyDecl.name))\(extensionSuffix)"
        )
        let storageSymbol = sema.symbols.define(
            kind: .field,
            name: storageName,
            fqName: ownerFQName + [storageName],
            declSite: propertyDecl.range,
            visibility: .private,
            flags: []
        )
        sema.symbols.setParentSymbol(objectSymbol, for: storageSymbol)
        sema.symbols.setDelegateStorageSymbol(storageSymbol, for: propertySymbol)
        return storageSymbol
    }

    private func syntheticObjectLiteralSymbols(
        for exprID: ExprID,
        interner: StringInterner
    ) -> (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString) {
        if let existing = driver.ctx.syntheticObjectLiteralSymbols(for: exprID) {
            return existing
        }
        let nominalSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let constructorSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let constructorName = interner.intern("kk_object_literal_\(exprID.rawValue)")
        let generated = (
            nominalSymbol: nominalSymbol,
            constructorSymbol: constructorSymbol,
            constructorName: constructorName
        )
        driver.ctx.registerSyntheticObjectLiteralSymbols(generated, for: exprID)
        return generated
    }

    private func ensureObjectLiteralGeneratedDecls(
        exprID: ExprID,
        superTypeCount: Int,
        objectValueType: TypeID,
        symbols: (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString),
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) {
        guard driver.ctx.markObjectLiteralEmitted(exprID) else {
            return
        }

        let nominalDeclID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbols.nominalSymbol)))
        driver.ctx.appendGeneratedCallableDecl(nominalDeclID)

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let storageSlotCount = max(1, superTypeCount)
        let slotCountExpr = arena.appendExpr(.intLiteral(Int64(storageSlotCount)), type: intType)
        let classIDExpr = arena.appendExpr(.intLiteral(0), type: intType)
        let objectEntityExpr = arena.appendTemporary(type: objectValueType)
        var body: [KIRInstruction] = [.beginBlock]
        body.append(.constValue(result: slotCountExpr, value: .intLiteral(Int64(storageSlotCount))))
        body.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
        body.append(.call(
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: objectEntityExpr,
            canThrow: false
        ))
        appendObjectVtableMethodRegistrations(
            objectValue: objectEntityExpr,
            nominalSymbol: symbols.nominalSymbol,
            driver: driver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body
        )
        body.append(.returnValue(objectEntityExpr))
        body.append(.endBlock)

        let constructorDeclID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: symbols.constructorSymbol,
                    name: symbols.constructorName,
                    params: [],
                    returnType: objectValueType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(constructorDeclID)
    }
}
