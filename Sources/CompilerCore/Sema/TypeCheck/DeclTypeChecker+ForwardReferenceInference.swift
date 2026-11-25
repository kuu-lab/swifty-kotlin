extension DeclTypeChecker {
    func makeInterfaceTypeCheckContext(
        interfaceDecl: InterfaceDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext
    ) -> TypeInferenceContext {
        let sema = ctx.sema
        var nestedObjects = interfaceDecl.nestedObjects
        if let companionObject = interfaceDecl.companionObject {
            nestedObjects.append(companionObject)
        }
        let typeArgs: [TypeArg] = sema.types.nominalTypeParameterSymbols(for: symbol).map {
            .invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0))))
        }
        let interfaceType = sema.types.make(.classType(ClassType(
            classSymbol: symbol, args: typeArgs, nullability: .nonNull
        )))
        let interfaceScope = buildClassMemberScope(
            ownerSymbol: symbol,
            ownerType: interfaceType,
            memberFunctions: interfaceDecl.memberFunctions,
            memberProperties: interfaceDecl.memberProperties,
            nestedClasses: interfaceDecl.nestedClasses,
            nestedObjects: nestedObjects,
            ctx: ctx
        )
        let label = sema.symbols.symbol(symbol)?.name ?? ctx.interner.intern("")
        return ctx
            .withOuterReceiver(label: label, type: interfaceType)
            .copying(
                scope: interfaceScope,
                implicitReceiverType: interfaceType,
                currentDeclSymbol: symbol,
                enclosingClassSymbol: symbol
            )
    }

    func makeClassTypeCheckContext(
        classDecl: ClassDecl,
        symbol: SymbolID,
        nestedObjects: [DeclID],
        ctx: TypeInferenceContext
    ) -> (classType: TypeID, classContext: TypeInferenceContext, primaryConstructorLocals: LocalBindings) {
        let sema = ctx.sema
        let classTypeArgs: [TypeArg] = sema.types.nominalTypeParameterSymbols(for: symbol).map {
            .invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0))))
        }
        let classType = sema.types.make(.classType(ClassType(
            classSymbol: symbol, args: classTypeArgs, nullability: .nonNull
        )))
        let classScope = buildClassMemberScope(
            ownerSymbol: symbol,
            ownerType: classType,
            memberFunctions: classDecl.memberFunctions,
            memberProperties: classDecl.memberProperties,
            nestedClasses: classDecl.nestedClasses,
            nestedObjects: nestedObjects,
            ctx: ctx
        )
        let classLabel = sema.symbols.symbol(symbol)?.name ?? ctx.interner.intern("")
        let classContext = ctx.withoutSuspensionContext()
            .withOuterReceiver(label: classLabel, type: classType, symbol: symbol)
            .copying(
                scope: classScope,
                implicitReceiverType: classType,
                currentDeclSymbol: symbol,
                enclosingClassSymbol: symbol
            )
        var primaryConstructorLocals = primaryConstructorParameterLocals(
            classDecl: classDecl,
            ctx: classContext
        )
        primaryConstructorLocals[ctx.interner.intern("this")] = (
            classType,
            SyntheticSymbolScheme.receiverParameterSymbol(for: symbol),
            false,
            true
        )
        return (classType, classContext, primaryConstructorLocals)
    }

    func precheckIndependentClassMemberProperties(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        var nestedObjects = classDecl.nestedObjects
        if let companionObject = classDecl.companionObject {
            nestedObjects.append(companionObject)
        }
        let (_, classContext, primaryConstructorLocals) = makeClassTypeCheckContext(
            classDecl: classDecl,
            symbol: symbol,
            nestedObjects: nestedObjects,
            ctx: ctx
        )

        for declID in nestedObjects {
            guard case let .objectDecl(objectDecl)? = ctx.ast.arena.decl(declID),
                  let objectSymbol = ctx.sema.bindings.declSymbols[declID]
            else { continue }
            precheckIndependentObjectMemberProperties(
                objectDecl, symbol: objectSymbol, ctx: classContext,
                solver: solver, diagnostics: diagnostics
            )
        }
        precheckIndependentNestedClassProperties(
            classDecl.nestedClasses, ctx: classContext,
            solver: solver, diagnostics: diagnostics
        )
        precheckIndependentMemberProperties(
            classDecl.memberProperties, ctx: classContext,
            initialLocals: primaryConstructorLocals,
            solver: solver, diagnostics: diagnostics
        )
    }

    func precheckIndependentInterfaceMemberProperties(
        _ interfaceDecl: InterfaceDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        var nestedObjects = interfaceDecl.nestedObjects
        if let companionObject = interfaceDecl.companionObject {
            nestedObjects.append(companionObject)
        }
        let interfaceContext = makeInterfaceTypeCheckContext(
            interfaceDecl: interfaceDecl,
            symbol: symbol,
            ctx: ctx
        )
        for declID in nestedObjects {
            guard case let .objectDecl(objectDecl)? = ctx.ast.arena.decl(declID),
                  let objectSymbol = ctx.sema.bindings.declSymbols[declID]
            else { continue }
            precheckIndependentObjectMemberProperties(
                objectDecl, symbol: objectSymbol, ctx: interfaceContext,
                solver: solver, diagnostics: diagnostics
            )
        }
        precheckIndependentNestedClassProperties(
            interfaceDecl.nestedClasses, ctx: interfaceContext,
            solver: solver, diagnostics: diagnostics
        )
        precheckIndependentMemberProperties(
            interfaceDecl.memberProperties, ctx: interfaceContext,
            solver: solver, diagnostics: diagnostics
        )
    }

    func makeObjectTypeCheckContext(
        objectDecl: ObjectDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext
    ) -> TypeInferenceContext {
        let sema = ctx.sema
        let objectType = sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
        let objectScope = buildClassMemberScope(
            ownerSymbol: symbol,
            ownerType: objectType,
            memberFunctions: objectDecl.memberFunctions,
            memberProperties: objectDecl.memberProperties,
            nestedClasses: objectDecl.nestedClasses,
            nestedObjects: objectDecl.nestedObjects,
            ctx: ctx
        )
        let objectLabel = sema.symbols.symbol(symbol)?.name ?? ctx.interner.intern("")
        return ctx.withoutSuspensionContext()
            .copying(outerReceiverTypes: ctx.singletonObjectOuterReceivers)
            .withOuterReceiver(label: objectLabel, type: objectType)
            .copying(
                scope: objectScope,
                implicitReceiverType: objectType,
                currentDeclSymbol: symbol,
                enclosingClassSymbol: symbol
            )
    }

    func precheckIndependentObjectMemberProperties(
        _ objectDecl: ObjectDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let objectContext = makeObjectTypeCheckContext(objectDecl: objectDecl, symbol: symbol, ctx: ctx)
        precheckIndependentMemberProperties(
            objectDecl.memberProperties, ctx: objectContext,
            solver: solver, diagnostics: diagnostics
        )
        precheckIndependentNestedClassProperties(
            objectDecl.nestedClasses, ctx: objectContext,
            solver: solver, diagnostics: diagnostics
        )
        for declID in objectDecl.nestedObjects {
            guard case let .objectDecl(nestedObject)? = ctx.ast.arena.decl(declID),
                  let nestedSymbol = ctx.sema.bindings.declSymbols[declID]
            else { continue }
            precheckIndependentObjectMemberProperties(
                nestedObject, symbol: nestedSymbol, ctx: objectContext,
                solver: solver, diagnostics: diagnostics
            )
        }
    }

    private func precheckIndependentNestedClassProperties(
        _ declIDs: [DeclID],
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        for declID in declIDs {
            guard case let .classDecl(classDecl)? = ctx.ast.arena.decl(declID),
                  let symbol = ctx.sema.bindings.declSymbols[declID]
            else { continue }
            let nestedContext = ctx.nestedClassContext(isInner: classDecl.isInner)
            precheckIndependentClassMemberProperties(
                classDecl, symbol: symbol, ctx: nestedContext,
                solver: solver, diagnostics: diagnostics
            )
        }
    }

    private func precheckIndependentMemberProperties(
        _ memberProperties: [DeclID],
        ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:],
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        allowFullInferredPrecheck: Bool = true
    ) {
        let sema = ctx.sema
        for declID in memberProperties {
            guard !driver.precheckedPropertyDecls.contains(declID),
                  case let .propertyDecl(property)? = ctx.ast.arena.decl(declID),
                  canSafelyPrecheckExplicitBackingFieldProperty(
                      property,
                      in: ctx,
                      initialLocals: initialLocals
                  ),
                  let propertySymbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            typeCheckBoundPropertyDecl(
                property,
                declID: declID,
                symbol: propertySymbol,
                ctx: ctx.with(currentDeclSymbol: propertySymbol),
                initialLocals: initialLocals,
                solver: solver,
                diagnostics: diagnostics
            )
            driver.precheckedPropertyDecls.insert(declID)
        }

        var didPrecheckProperty: Bool
        repeat {
            didPrecheckProperty = false
            for declID in memberProperties {
                guard !driver.precheckedPropertyDecls.contains(declID),
                      let decl = ctx.ast.arena.decl(declID),
                      case let .propertyDecl(property) = decl,
                      let propertySymbol = sema.bindings.declSymbols[declID]
                else {
                    continue
                }
                if allowFullInferredPrecheck,
                   canSafelyPrecheckInferredProperty(
                       property,
                       symbol: propertySymbol,
                       in: ctx,
                       initialLocals: initialLocals
                   ) {
                    typeCheckBoundPropertyDecl(
                        property,
                        declID: declID,
                        symbol: propertySymbol,
                        ctx: ctx.with(currentDeclSymbol: propertySymbol),
                        initialLocals: initialLocals,
                        solver: solver,
                        diagnostics: diagnostics
                    )
                    driver.precheckedPropertyDecls.insert(declID)
                    didPrecheckProperty = true
                    continue
                }
                // A custom accessor body cannot run early: it may read member
                // types this pass has not resolved yet, and a speculative
                // check could succeed against the Any? placeholder while
                // recording wrong bindings. A safe initializer still fixes
                // the property's type on its own, so publish that type while
                // the header placeholder is in place; the source-order pass
                // then re-checks the whole declaration, accessors included.
                if sema.symbols.propertyType(for: propertySymbol) == sema.types.nullableAnyType,
                   canPublishInferredPropertyTypeEarly(
                       property,
                       in: ctx,
                       initialLocals: initialLocals
                   )
                {
                    let diagnosticSnapshot = diagnostics.count
                    let nominalDeclsCheckedBefore = driver.localNominalDeclChecks.count
                    typeCheckBoundPropertyDecl(
                        property,
                        declID: declID,
                        symbol: propertySymbol,
                        ctx: ctx.with(currentDeclSymbol: propertySymbol),
                        initialLocals: initialLocals,
                        solver: solver,
                        diagnostics: diagnostics,
                        checkAccessorBodies: false
                    )
                    diagnostics.truncate(to: diagnosticSnapshot)
                    driver.markLocalNominalRechecks(since: nominalDeclsCheckedBefore)
                    didPrecheckProperty = true
                    continue
                }
                if !driver.publishedInferredPropertyDecls.contains(declID),
                   canSafelyPrecheckInferredPropertyInitializerType(
                       property,
                       in: ctx,
                       initialLocals: initialLocals
                   )
                {
                    publishInferredPropertyInitializerType(
                        property,
                        symbol: propertySymbol,
                        in: ctx,
                        initialLocals: initialLocals
                    )
                    driver.publishedInferredPropertyDecls.insert(declID)
                    didPrecheckProperty = true
                }
                if !driver.publishedInferredPropertyDecls.contains(declID),
                   canPublishInferredGetterPropertyType(
                       property,
                       in: ctx,
                       initialLocals: initialLocals
                   )
                {
                    publishInferredGetterPropertyType(
                        property,
                        symbol: propertySymbol,
                        in: ctx,
                        initialLocals: initialLocals
                    )
                    driver.publishedInferredPropertyDecls.insert(declID)
                    didPrecheckProperty = true
                }
                if !allowFullInferredPrecheck,
                   !driver.publishedInferredPropertyDecls.contains(declID),
                   property.type == nil,
                   property.delegateExpression != nil || property.receiverType != nil,
                   publishInferredDelegatedOrExtensionPropertyType(
                       property,
                       symbol: propertySymbol,
                       in: ctx,
                       initialLocals: initialLocals
                   )
                {
                    driver.publishedInferredPropertyDecls.insert(declID)
                    didPrecheckProperty = true
                }
            }
        } while didPrecheckProperty
    }

    func canSafelyPrecheckInferredPropertyInitializerType(
        _ property: PropertyDecl,
        in ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:]
    ) -> Bool {
        guard property.type == nil,
              property.explicitBackingField == nil,
              property.getter == nil,
              property.receiverType == nil,
              property.contextReceivers.isEmpty,
              property.delegateExpression == nil,
              let initializer = property.initializer,
              let type = safePrecheckExpressionType(
                  initializer,
                  in: ctx,
                  locals: initialLocals
              )
        else {
            return false
        }
        return type != ctx.sema.types.nullableNothingType
    }

    func publishInferredPropertyInitializerType(
        _ property: PropertyDecl,
        symbol: SymbolID,
        in ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:]
    ) {
        guard let initializer = property.initializer,
              driver.checkingInferredProperties.insert(symbol).inserted
        else {
            return
        }
        defer { driver.checkingInferredProperties.remove(symbol) }
        // The declaration is not marked as checked, so the authoritative pass
        // rechecks it and owns all of its diagnostics. Roll back anything the
        // speculative initializer inference emitted to avoid duplicates.
        let nominalDeclsCheckedBefore = driver.localNominalDeclChecks.count
        let diagnosticSnapshot = ctx.sema.diagnostics.count
        defer {
            ctx.sema.diagnostics.truncate(to: diagnosticSnapshot)
            driver.markLocalNominalRechecks(since: nominalDeclsCheckedBefore)
        }
        var locals = initialLocals
        let inferredType = driver.inferExpr(
            initializer,
            ctx: ctx.with(initializingPropertySymbol: symbol),
            locals: &locals,
            expectedType: nil
        )
        guard inferredType != ctx.sema.types.errorType else {
            return
        }
        ctx.sema.symbols.setPropertyType(
            exposedAnonymousType(inferredType, symbol: symbol, range: property.range, ctx: ctx),
            for: symbol
        )
    }

    func canPublishInferredGetterPropertyType(
        _ property: PropertyDecl,
        in ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:]
    ) -> Bool {
        guard property.type == nil,
              property.explicitBackingField == nil,
              property.receiverType == nil,
              property.delegateExpression == nil,
              !property.isVar,
              property.initializer == nil,
              property.contextReceivers.isEmpty,
              property.typeParams.isEmpty,
              property.setter == nil,
              let getter = property.getter,
              getter.returnType == nil,
              case let .expr(bodyExpr, _) = getter.body
        else {
            return false
        }
        let previousFlag = requiresSafePrecheckCastOperands
        requiresSafePrecheckCastOperands = false
        defer { requiresSafePrecheckCastOperands = previousFlag }
        guard let type = safePrecheckExpressionType(bodyExpr, in: ctx, locals: initialLocals)
        else {
            return false
        }
        return type != ctx.sema.types.nullableNothingType
    }

    func publishInferredGetterPropertyType(
        _ property: PropertyDecl,
        symbol: SymbolID,
        in ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:]
    ) {
        guard let getter = property.getter,
              case let .expr(bodyExpr, _) = getter.body,
              driver.checkingInferredProperties.insert(symbol).inserted
        else {
            return
        }
        defer { driver.checkingInferredProperties.remove(symbol) }
        let previousFlag = requiresSafePrecheckCastOperands
        requiresSafePrecheckCastOperands = false
        defer { requiresSafePrecheckCastOperands = previousFlag }
        guard let type = safePrecheckExpressionType(bodyExpr, in: ctx, locals: initialLocals),
              type != ctx.sema.types.nullableNothingType,
              type != ctx.sema.types.errorType
        else {
            return
        }
        ctx.sema.symbols.setPropertyType(
            exposedAnonymousType(type, symbol: symbol, range: property.range, ctx: ctx),
            for: symbol
        )
    }

    private func safePrecheckInferredDelegatedOrExtensionPropertyType(
        _ property: PropertyDecl,
        symbol: SymbolID,
        in ctx: TypeInferenceContext,
        initialLocals: LocalBindings
    ) -> TypeID? {
        guard property.type == nil,
              property.explicitBackingField == nil
        else {
            return nil
        }

        let previousFlag = requiresSafePrecheckCallArguments
        let previousCastFlag = requiresSafePrecheckCastOperands
        requiresSafePrecheckCallArguments = true
        requiresSafePrecheckCastOperands = true
        defer {
            requiresSafePrecheckCallArguments = previousFlag
            requiresSafePrecheckCastOperands = previousCastFlag
        }

        if let receiverType = ctx.sema.symbols.extensionPropertyReceiverType(for: symbol) {
            guard !property.isVar,
                  property.setter == nil,
                  property.receiverType != nil,
                  property.typeParams.isEmpty,
                  property.contextReceivers.isEmpty,
                  property.initializer == nil,
                  property.delegateExpression == nil,
                  let getter = property.getter,
                  getter.returnType == nil,
                  case let .expr(bodyExpr, _) = getter.body
            else {
                return nil
            }
            let getterContext = ctx.copying(
                implicitReceiverType: receiverType,
                currentDeclSymbol: symbol
            ).withOuterReceiver(
                label: property.name,
                type: receiverType,
                symbol: SyntheticSymbolScheme.receiverParameterSymbol(for: symbol)
            )
            guard let type = safePrecheckExpressionType(
                bodyExpr,
                in: getterContext,
                locals: initialLocals
            ),
                type != ctx.sema.types.nullableNothingType,
                type != ctx.sema.types.errorType
            else {
                return nil
            }
            return type
        }

        guard property.getter == nil,
              property.setter == nil || property.setter?.body == .unit,
              property.receiverType == nil,
              !property.isVar,
              property.initializer == nil,
              property.delegateBodyParams.isEmpty,
              let delegateExpression = property.delegateExpression,
              StdlibDelegateKind.detect(
                  delegateExpr: delegateExpression,
                  ast: ctx.ast,
                  interner: ctx.interner
              ) == .lazy,
              case let .expr(bodyExpr, _) = property.delegateBody
        else {
            return nil
        }
        let valueType: TypeID?
        if case let .call(_, typeArgs, _, _)? = ctx.ast.arena.expr(delegateExpression),
           let firstTypeArg = typeArgs.first
        {
            valueType = safePrecheckTypeRef(firstTypeArg, in: ctx)
        } else {
            valueType = safePrecheckExpressionType(bodyExpr, in: ctx, locals: initialLocals)
        }
        guard let valueType,
              valueType != ctx.sema.types.nullableNothingType,
              valueType != ctx.sema.types.errorType
        else {
            return nil
        }
        return valueType
    }

    func publishInferredDelegatedOrExtensionPropertyType(
        _ property: PropertyDecl,
        symbol: SymbolID,
        in ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:]
    ) -> Bool {
        guard driver.checkingInferredProperties.insert(symbol).inserted else {
            return false
        }
        defer { driver.checkingInferredProperties.remove(symbol) }
        guard let type = safePrecheckInferredDelegatedOrExtensionPropertyType(
            property,
            symbol: symbol,
            in: ctx,
            initialLocals: initialLocals
        ) else {
            return false
        }
        ctx.sema.symbols.setPropertyType(
            exposedAnonymousType(type, symbol: symbol, range: property.range, ctx: ctx),
            for: symbol
        )
        return true
    }

    func canSafelyPrecheckExplicitBackingFieldProperty(
        _ property: PropertyDecl,
        in ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:]
    ) -> Bool {
        guard !property.isVar,
              property.type != nil,
              property.getter == nil,
              property.setter == nil,
              property.delegateExpression == nil,
              property.receiverType == nil,
              let explicitField = property.explicitBackingField,
              let initializer = explicitField.initializer,
              case let .call(callee, typeArgs, args, _)? = ctx.ast.arena.expr(initializer),
              typeArgs.isEmpty,
              args.isEmpty,
              case let .nameRef(name, _)? = ctx.ast.arena.expr(callee),
              initialLocals[name] == nil,
              name == ctx.interner.intern("mutableListOf")
        else {
            return false
        }

        let knownNames = KnownCompilerNames(interner: ctx.interner)
        let factoryFQName = [knownNames.kotlin, knownNames.collections, name]
        let visibleCandidates = ctx.cachedScopeLookup(name).compactMap(ctx.cachedSymbol)
        return visibleCandidates.contains(where: { $0.kind == .function && $0.fqName == factoryFQName })
            && visibleCandidates.allSatisfy { $0.fqName == factoryFQName }
    }

    func precheckIndependentObjectLiteralMemberProperties(
        _ memberProperties: [DeclID],
        ctx: TypeInferenceContext,
        initialLocals: LocalBindings,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        // Object literals are rechecked by `typeCheckLocalNominalMemberProperties`;
        // marking these declarations fully prechecked would skip that pass and
        // leave member bodies reading placeholder property types (KUU-4610).
        // Published inferred types are keyed by declaration, so clear them for
        // this literal: a rolled-back nominal check resets property headers and
        // must be able to publish the same types again on the retry.
        for declID in memberProperties {
            driver.publishedInferredPropertyDecls.remove(declID)
        }
        precheckIndependentMemberProperties(
            memberProperties,
            ctx: ctx,
            initialLocals: initialLocals,
            solver: solver,
            diagnostics: diagnostics,
            allowFullInferredPrecheck: false
        )
    }

    func canSafelyPrecheckInferredProperty(
        _ property: PropertyDecl,
        symbol: SymbolID,
        in ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:]
    ) -> Bool {
        // This gate decides whether the whole declaration — initializer or
        // accessor body included — can run the full check ahead of source
        // order without emitting diagnostics for not-yet-resolved references.
        // Constructor result types pinned by explicit type arguments must not
        // bypass that requirement, so require every call argument to be safe
        // while probing (KUU-4280). The publish-type-only paths below keep the
        // lenient probe and still surface the pinned type.
        let previousFlag = requiresSafePrecheckCallArguments
        let previousCastFlag = requiresSafePrecheckCastOperands
        requiresSafePrecheckCallArguments = true
        requiresSafePrecheckCastOperands = true
        defer {
            requiresSafePrecheckCallArguments = previousFlag
            requiresSafePrecheckCastOperands = previousCastFlag
        }
        return canSafelyPrecheckInferredPropertyProbing(
            property,
            symbol: symbol,
            in: ctx,
            initialLocals: initialLocals
        )
    }

    private func canSafelyPrecheckInferredPropertyProbing(
        _ property: PropertyDecl,
        symbol: SymbolID,
        in ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:]
    ) -> Bool {
        guard property.type == nil,
              property.explicitBackingField == nil
        else {
            return false
        }

        if let receiverType = ctx.sema.symbols.extensionPropertyReceiverType(for: symbol) {
            guard !property.isVar,
                  property.setter == nil,
                  property.receiverType != nil,
                  property.typeParams.isEmpty,
                  property.contextReceivers.isEmpty,
                  property.initializer == nil,
                  property.delegateExpression == nil,
                  let getter = property.getter,
                  getter.returnType == nil,
                  case let .expr(bodyExpr, _) = getter.body
            else {
                return false
            }

            let getterContext = ctx.copying(
                implicitReceiverType: receiverType,
                currentDeclSymbol: symbol
            ).withOuterReceiver(
                label: property.name,
                type: receiverType,
                symbol: SyntheticSymbolScheme.receiverParameterSymbol(for: symbol)
            )
            guard let type = safePrecheckExpressionType(
                bodyExpr,
                in: getterContext,
                locals: initialLocals
            ) else {
                return false
            }
            return type != ctx.sema.types.nullableNothingType
        }

        if let getter = property.getter {
            guard property.receiverType == nil,
                  !property.isVar,
                  property.initializer == nil,
                  property.delegateExpression == nil,
                  property.contextReceivers.isEmpty,
                  property.typeParams.isEmpty,
                  property.setter == nil,
                  getter.returnType == nil,
                  case let .expr(bodyExpr, _) = getter.body,
                  let type = safePrecheckExpressionType(bodyExpr, in: ctx, locals: initialLocals)
            else {
                return false
            }
            return type != ctx.sema.types.nullableNothingType
        }

        guard property.getter == nil,
              property.setter == nil || property.setter?.body == .unit,
              property.receiverType == nil
        else {
            return false
        }

        if property.delegateExpression == nil,
           let initializer = property.initializer
        {
            guard let type = safePrecheckExpressionType(
                initializer,
                in: ctx,
                locals: initialLocals
            ) else {
                return false
            }
            return type != ctx.sema.types.nullableNothingType
        }

        guard !property.isVar,
              property.initializer == nil,
              property.delegateBodyParams.isEmpty,
              let delegateExpression = property.delegateExpression,
              StdlibDelegateKind.detect(
                  delegateExpr: delegateExpression,
                  ast: ctx.ast,
                  interner: ctx.interner
              ) == .lazy,
              case let .expr(bodyExpr, _) = property.delegateBody,
              let type = safePrecheckExpressionType(
                  bodyExpr,
                  in: ctx,
                  locals: initialLocals
              )
        else {
            return false
        }
        return type != ctx.sema.types.nullableNothingType
    }

    func canPublishInferredPropertyTypeEarly(
        _ property: PropertyDecl,
        in ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:]
    ) -> Bool {
        guard property.type == nil,
              property.explicitBackingField == nil,
              property.receiverType == nil,
              property.delegateExpression == nil,
              let initializer = property.initializer
        else {
            return false
        }
        let hasAccessorBody = [property.getter, property.setter].contains { accessor in
            guard let body = accessor?.body else { return false }
            return body != .unit
        }
        guard hasAccessorBody,
              let type = safePrecheckExpressionType(
                  initializer,
                  in: ctx,
                  locals: initialLocals
              )
        else {
            return false
        }
        return type != ctx.sema.types.nullableNothingType
    }

    func safePrecheckExpressionType(
        _ exprID: ExprID,
        in ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        guard let expr = ctx.ast.arena.expr(exprID) else { return nil }
        let types = ctx.sema.types

        switch expr {
        case .intLiteral:
            return types.intType
        case .longLiteral:
            return types.longType
        case .uintLiteral:
            return types.uintType
        case .ulongLiteral:
            return types.ulongType
        case .floatLiteral:
            return types.floatType
        case .doubleLiteral:
            return types.doubleType
        case .charLiteral:
            return types.charType
        case .boolLiteral:
            return types.booleanType
        case .stringLiteral:
            return types.stringType
        case .nullLiteral:
            return types.nullableNothingType
        case let .stringTemplate(parts, _):
            for part in parts {
                if case let .expression(expression) = part,
                   safePrecheckExpressionType(expression, in: ctx, locals: locals) == nil
                {
                    return nil
                }
            }
            return types.stringType
        case let .nameRef(name, _):
            return safePrecheckNameReference(name, in: ctx, locals: locals)
        case let .thisRef(label, _):
            let thisType: TypeID? = if let label {
                ctx.resolveQualifiedThis(label: label)
            } else {
                ctx.implicitReceiverType
            }
            guard let thisType else { return nil }
            return isSafePrecheckValueType(thisType, in: ctx) ? thisType : nil
        case let .unaryExpr(op, operand, _):
            guard let operandType = safePrecheckExpressionType(operand, in: ctx, locals: locals) else {
                return nil
            }
            if op == .not {
                return operandType == types.booleanType ? types.booleanType : nil
            }
            return isSafeNumericType(operandType, in: ctx) ? operandType : nil
        case let .binary(op, lhs, rhs, _):
            return safePrecheckBinaryType(op, lhs: lhs, rhs: rhs, in: ctx, locals: locals)
        case let .isCheck(operand, _, _, _):
            guard safePrecheckExpressionType(operand, in: ctx, locals: locals) != nil else {
                return nil
            }
            return types.booleanType
        case let .asCast(operand, typeRefID, isSafe, range):
            return safePrecheckCastType(
                operand: operand, typeRefID: typeRefID, isSafe: isSafe, range: range,
                in: ctx, locals: locals
            )
        case let .nullAssert(operand, _):
            guard let operandType = safePrecheckExpressionType(operand, in: ctx, locals: locals) else {
                return nil
            }
            let nonNullType = types.makeNonNullable(operandType)
            return isSafePrecheckValueType(nonNullType, in: ctx) ? nonNullType : nil
        case .call:
            return safePrecheckTopLevelCall(exprID, in: ctx, locals: locals)
        case .memberCall:
            if let enumEntryType = safePrecheckQualifiedEnumEntryType(
                exprID, in: ctx, locals: locals
            ),
               isSafePrecheckValueType(enumEntryType, in: ctx)
            {
                return enumEntryType
            }
            return safePrecheckMemberCall(exprID, in: ctx, locals: locals)
        case .safeMemberCall:
            return safePrecheckSafeMemberCall(exprID, in: ctx, locals: locals)
        default:
            return nil
        }
    }

    private func safePrecheckCastType(
        operand: ExprID,
        typeRefID: TypeRefID,
        isSafe: Bool,
        range: SourceRange,
        in ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        let operandType = safePrecheckExpressionType(operand, in: ctx, locals: locals)
        if requiresSafePrecheckCastOperands, operandType == nil {
            return nil
        }
        var targetType = driver.helpers.resolveTypeRef(
            typeRefID,
            ast: ctx.ast,
            sema: ctx.sema,
            interner: ctx.interner,
            scope: ctx.scope,
            diagnostics: nil,
            inferenceContext: ctx,
            usageRange: range,
            allowBareGenericTypeAliasProjection: true
        )
        guard targetType != ctx.sema.types.errorType else { return nil }
        if case let .classType(targetClass) = ctx.sema.types.kind(of: targetType),
           targetClass.args.isEmpty,
           !ctx.sema.types.nominalTypeParameterSymbols(for: targetClass.classSymbol).isEmpty
        {
            guard let operandType,
                  case let .classType(sourceClass) = ctx.sema.types.kind(
                      of: ctx.sema.types.makeNonNullable(operandType)
                  ),
                  let inferredArgs = ctx.sema.types.narrowedSubtypeArgs(
                      forSubtype: targetClass.classSymbol,
                      givenSupertype: sourceClass.classSymbol,
                      supertypeArgs: sourceClass.args
                  )
            else {
                return nil
            }
            targetType = ctx.sema.types.make(.classType(ClassType(
                classSymbol: targetClass.classSymbol,
                args: inferredArgs,
                nullability: targetClass.nullability
            )))
        }
        let resultType = isSafe ? ctx.sema.types.makeNullable(targetType) : targetType
        return isSafePrecheckValueType(resultType, in: ctx) ? resultType : nil
    }

    private func safePrecheckNameReference(
        _ name: InternedString,
        in ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        if let local = locals[name] {
            let type = safePrecheckFlowType(for: local.symbol, fallback: local.type, in: ctx)
            return local.isInitialized && isSafePrecheckValueType(type, in: ctx) ? type : nil
        }
        // Match expression inference's receiver tower before falling back to
        // lexical names. An unresolved inherited member can shadow a concrete
        // top-level property and must keep this initializer on the normal pass.
        for receiver in ctx.implicitReceiverMemberLookupEntries() {
            if let property = driver.helpers.lookupMemberProperty(
                named: name, receiverType: receiver.type, sema: ctx.sema
            ),
               let propertySymbol = ctx.sema.symbols.symbol(property.symbol),
               ctx.visibilityChecker.isAccessible(
                   propertySymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                let type = safePrecheckFlowType(for: property.symbol, fallback: property.type, in: ctx)
                return isSafePrecheckValueType(type, in: ctx) ? type : nil
            }
        }
        let candidates = ctx.scope.lookup(name)
        guard candidates.count == 1,
              let symbol = ctx.sema.symbols.symbol(candidates[0])
        else {
            return nil
        }
        var valueSymbol = symbol
        if symbol.kind == .class || symbol.kind == .enumClass || symbol.kind == .interface,
           let companion = ctx.sema.symbols.companionObjectSymbolIfKnown(for: symbol.id),
           let companionSymbol = ctx.sema.symbols.symbol(companion)
        {
            valueSymbol = companionSymbol
        }
        if valueSymbol.kind == .object {
            if valueSymbol.id == ctx.sema.types.unitClassSymbol {
                return ctx.sema.types.unitType
            }
            return ctx.sema.symbols.propertyType(for: valueSymbol.id)
                ?? ctx.sema.types.make(.classType(ClassType(
                    classSymbol: valueSymbol.id, args: [], nullability: .nonNull
                )))
        }
        guard symbol.kind == .property || symbol.kind == .field,
              let declaredType = ctx.sema.symbols.propertyType(for: candidates[0])
        else {
            return nil
        }
        let type = safePrecheckFlowType(for: candidates[0], fallback: declaredType, in: ctx)
        return isSafePrecheckValueType(type, in: ctx) ? type : nil
    }

    private func safePrecheckTopLevelCall(
        _ exprID: ExprID,
        in ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        guard case let .call(callee, typeArgs, args, _)? = ctx.ast.arena.expr(exprID),
              case let .nameRef(name, _)? = ctx.ast.arena.expr(callee),
              locals[name] == nil
        else {
            return nil
        }
        let namedCandidates = ctx.cachedScopeLookup(name)
        if let arrayType = safePrecheckArrayOfCall(
            name,
            typeArgs: typeArgs,
            args: args,
            namedCandidates: namedCandidates,
            in: ctx,
            locals: locals
        ) {
            return arrayType
        }
        var effectiveClassSymbol: SymbolID?
        var candidatesShareOneClass = true
        for candidate in namedCandidates {
            guard let resolved = precheckEffectiveClassSymbol(for: candidate, in: ctx),
                  effectiveClassSymbol == nil || effectiveClassSymbol == resolved
            else {
                candidatesShareOneClass = false
                break
            }
            effectiveClassSymbol = resolved
        }
        if candidatesShareOneClass,
           let classSymbolID = effectiveClassSymbol,
           let symbol = ctx.sema.symbols.symbol(classSymbolID),
           symbol.kind == .class || symbol.kind == .enumClass
        {
            // A pinned constructor result does not prove its arguments are
            // resolvable yet. `canSafelyPrecheckInferredProperty` raises this
            // flag when it decides whether a whole declaration can be checked
            // early, so an argument that only resolves on the source-order
            // pass cannot produce a spurious diagnostic here (KUU-4280).
            if requiresSafePrecheckCallArguments,
               !args.allSatisfy({ safePrecheckExpressionType($0.expr, in: ctx, locals: locals) != nil })
            {
                return nil
            }
            let typeParameters = ctx.sema.types.nominalTypeParameterSymbols(for: symbol.id)
            if typeArgs.isEmpty && typeParameters.isEmpty {
                return ctx.sema.types.make(.classType(ClassType(
                    classSymbol: symbol.id, args: [], nullability: .nonNull
                )))
            }
            let initName = ctx.interner.intern("<init>")
            let constructorSymbols = ctx.sema.symbols.lookupAll(fqName: symbol.fqName + [initName])
            if typeArgs.isEmpty {
                var argumentTypes: [TypeID] = []
                argumentTypes.reserveCapacity(args.count)
                for argument in args {
                    guard argument.label == nil, !argument.isSpread,
                          let argumentType = safePrecheckExpressionType(
                              argument.expr, in: ctx, locals: locals
                          )
                    else {
                        return nil
                    }
                    argumentTypes.append(argumentType)
                }
                var resolvedClassArgs: [TypeArg]? = nil
                var sawApplicableConstructor = false
                for ctor in constructorSymbols {
                    guard let signature = ctx.sema.symbols.functionSignature(for: ctor),
                          let bindings = precheckArgumentFitsSignature(
                              signature,
                              candidate: ctor,
                              argumentTypes: argumentTypes,
                              receiverType: nil,
                              bindableTypeParameters: Set(signature.typeParameterSymbols),
                              in: ctx
                          )
                    else {
                        continue
                    }
                    sawApplicableConstructor = true
                    var ctorArgs: [TypeArg] = []
                    var allBound = true
                    for typeParameter in typeParameters {
                        guard let bound = bindings.bindings[typeParameter] else {
                            allBound = false
                            break
                        }
                        ctorArgs.append(.invariant(bound))
                    }
                    guard allBound else { return nil }
                    if let resolvedClassArgs, resolvedClassArgs != ctorArgs {
                        return nil
                    }
                    resolvedClassArgs = ctorArgs
                }
                guard sawApplicableConstructor, let resolvedClassArgs else { return nil }
                return ctx.sema.types.make(.classType(ClassType(
                    classSymbol: symbol.id, args: resolvedClassArgs, nullability: .nonNull
                )))
            }
            guard typeArgs.count == typeParameters.count, !typeArgs.isEmpty,
                  !constructorSymbols.isEmpty,
                  constructorSymbols.allSatisfy({ ctor in
                      guard let signature = ctx.sema.symbols.functionSignature(for: ctor) else {
                          return false
                      }
                      return signature.valueParameterHasDefaultValues.allSatisfy { !$0 }
                  })
            else {
                return nil
            }
            var resolvedArgs: [TypeArg] = []
            resolvedArgs.reserveCapacity(typeArgs.count)
            for typeArg in typeArgs {
                guard let resolved = safePrecheckTypeRef(typeArg, in: ctx) else {
                    return nil
                }
                resolvedArgs.append(.invariant(resolved))
            }
            return ctx.sema.types.make(.classType(ClassType(
                classSymbol: symbol.id, args: resolvedArgs, nullability: .nonNull
            )))
        }
        guard typeArgs.isEmpty else { return nil }
        if !args.isEmpty {
            guard args.allSatisfy({ $0.label == nil && !$0.isSpread }) else {
                return nil
            }
            var argumentTypes: [TypeID] = []
            argumentTypes.reserveCapacity(args.count)
            for argument in args {
                guard let argumentType = safePrecheckExpressionType(
                    argument.expr, in: ctx, locals: locals
                ) else {
                    return nil
                }
                argumentTypes.append(argumentType)
            }
            for receiver in ctx.implicitReceiverMemberLookupEntries() {
                let receiverType = ctx.sema.types.makeNonNullable(receiver.type)
                let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: name,
                    receiverType: receiverType,
                    sema: ctx.sema,
                    interner: ctx.interner
                ).filter { candidate in
                    guard ctx.sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
                          let signature = ctx.sema.symbols.functionSignature(for: candidate)
                    else {
                        return false
                    }
                    return signature.contextReceiverTypes.isEmpty
                }
                let applicableMembers = memberCandidates.filter { candidate in
                    guard let signature = ctx.sema.symbols.functionSignature(for: candidate) else {
                        return false
                    }
                    return precheckArgumentFitsSignature(
                        signature,
                        candidate: candidate,
                        argumentTypes: argumentTypes,
                        receiverType: receiverType,
                        in: ctx
                    ) != nil
                }
                if !applicableMembers.isEmpty {
                    return safePrecheckCallResultType(
                        applicableMembers,
                        receiverType: receiverType,
                        argumentTypes: argumentTypes,
                        in: ctx
                    )
                }
                if driver.helpers.lookupMemberProperty(
                    named: name,
                    receiverType: receiver.type,
                    sema: ctx.sema
                ) != nil {
                    return nil
                }
            }
            var scopeLevel = ctx.scope as? BaseScope
            var scopeCandidates: [SymbolID] = []
            while let level = scopeLevel {
                let bound = level.candidates(for: name)
                if bound.isEmpty {
                    scopeLevel = level.parent as? BaseScope
                    continue
                }
                var memberFunctions: [SymbolID] = []
                var bindsOtherDeclaration = false
                for candidate in bound {
                    guard let symbol = ctx.cachedSymbol(candidate),
                          symbol.kind == .function,
                          let signature = ctx.sema.symbols.functionSignature(for: candidate),
                          signature.receiverType != nil
                    else {
                        bindsOtherDeclaration = true
                        break
                    }
                    memberFunctions.append(candidate)
                }
                if bindsOtherDeclaration {
                    scopeCandidates = bound
                    break
                }
                var applicableMembers: [(candidate: SymbolID, receiverType: TypeID)] = []
                for candidate in memberFunctions {
                    guard let signature = ctx.sema.symbols.functionSignature(for: candidate),
                          signature.contextReceiverTypes.isEmpty,
                          let declaredReceiver = signature.receiverType,
                          case let .classType(declaredClass) = ctx.sema.types.kind(
                              of: ctx.sema.types.makeNonNullable(declaredReceiver)
                          )
                    else {
                        continue
                    }
                    for entry in ctx.implicitReceiverMemberLookupEntries() {
                        guard case let .classType(receiverClass) = ctx.sema.types.kind(
                            of: ctx.sema.types.makeNonNullable(entry.type)
                        ) else {
                            continue
                        }
                        guard ctx.sema.types.isNominalSubtypeSymbol(
                            receiverClass.classSymbol, of: declaredClass.classSymbol
                        ) || ctx.sema.symbols.companionObjectSymbol(
                            for: receiverClass.classSymbol
                        ) == declaredClass.classSymbol
                        else {
                            continue
                        }
                        let supplyingReceiver = ctx.sema.types.makeNonNullable(entry.type)
                        if precheckArgumentFitsSignature(
                            signature,
                            candidate: candidate,
                            argumentTypes: argumentTypes,
                            receiverType: supplyingReceiver,
                            in: ctx
                        ) != nil {
                            applicableMembers.append((candidate, supplyingReceiver))
                            break
                        }
                    }
                }
                if !applicableMembers.isEmpty {
                    var grouped: [TypeID: [SymbolID]] = [:]
                    var receiverOrder: [TypeID] = []
                    for member in applicableMembers {
                        if grouped[member.receiverType] == nil {
                            receiverOrder.append(member.receiverType)
                        }
                        grouped[member.receiverType, default: []].append(member.candidate)
                    }
                    var resultType: TypeID?
                    for receiverType in receiverOrder {
                        guard let groupResult = safePrecheckCallResultType(
                            grouped[receiverType] ?? [],
                            receiverType: receiverType,
                            argumentTypes: argumentTypes,
                            in: ctx
                        ) else {
                            return nil
                        }
                        if let resultType, resultType != groupResult {
                            return nil
                        }
                        resultType = groupResult
                    }
                    return resultType
                }
                scopeLevel = level.parent as? BaseScope
            }
            let candidates = scopeCandidates.filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      let signature = ctx.sema.symbols.functionSignature(for: candidate),
                      !ctx.isExpectDeclarationSupersededByActual(candidate),
                      !ctx.isImportedSymbolShadowedBySource(candidate)
                else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.contextReceiverTypes.isEmpty
            }
            if !candidates.isEmpty {
                return safePrecheckCallResultType(
                    candidates,
                    argumentTypes: argumentTypes,
                    in: ctx
                )
            }
            return nil
        }

        for receiver in ctx.implicitReceiverMemberLookupEntries() {
            let receiverType = ctx.sema.types.makeNonNullable(receiver.type)
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: name,
                receiverType: receiverType,
                sema: ctx.sema,
                interner: ctx.interner
            ).filter { candidate in
                guard ctx.sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
                      let signature = ctx.sema.symbols.functionSignature(for: candidate)
                else {
                    return false
                }
                return signature.contextReceiverTypes.isEmpty
                    && canBeCalledWithoutArguments(signature)
            }
            if !memberCandidates.isEmpty {
                return safePrecheckCallResultType(
                    memberCandidates,
                    receiverType: receiverType,
                    in: ctx
                )
            }
            if let property = driver.helpers.lookupMemberProperty(
                named: name,
                receiverType: receiver.type,
                sema: ctx.sema
            ) {
                let calleeType = safePrecheckFlowType(
                    for: property.symbol,
                    fallback: property.type,
                    in: ctx
                )
                return safePrecheckInvokeCall(on: calleeType, in: ctx)
            }
        }

        var scopeLevel = ctx.scope as? BaseScope
        var scopeCandidates: [SymbolID] = []
        while let level = scopeLevel {
            let bound = level.candidates(for: name)
            if bound.isEmpty {
                scopeLevel = level.parent as? BaseScope
                continue
            }
            var memberFunctions: [SymbolID] = []
            var bindsOtherDeclaration = false
            for candidate in bound {
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      let signature = ctx.sema.symbols.functionSignature(for: candidate),
                      signature.receiverType != nil
                else {
                    bindsOtherDeclaration = true
                    break
                }
                memberFunctions.append(candidate)
            }
            if bindsOtherDeclaration {
                scopeCandidates = bound
                break
            }
            let applicableMembers = memberFunctions.filter { candidate in
                guard let signature = ctx.sema.symbols.functionSignature(for: candidate),
                      signature.contextReceiverTypes.isEmpty,
                      canBeCalledWithoutArguments(signature),
                      let declaredReceiver = signature.receiverType,
                      case let .classType(declaredClass) = ctx.sema.types.kind(
                          of: ctx.sema.types.makeNonNullable(declaredReceiver)
                      )
                else {
                    return false
                }
                return ctx.implicitReceiverMemberLookupEntries().contains { entry in
                    guard case let .classType(receiverClass) = ctx.sema.types.kind(
                        of: ctx.sema.types.makeNonNullable(entry.type)
                    ) else {
                        return false
                    }
                    return ctx.sema.types.isNominalSubtypeSymbol(
                        receiverClass.classSymbol, of: declaredClass.classSymbol
                    ) || ctx.sema.symbols.companionObjectSymbol(
                        for: receiverClass.classSymbol
                    ) == declaredClass.classSymbol
                }
            }
            if !applicableMembers.isEmpty {
                let dispatchReceiver = applicableMembers.first
                    .flatMap { ctx.sema.symbols.functionSignature(for: $0)?.receiverType }
                return safePrecheckCallResultType(
                    applicableMembers,
                    receiverType: dispatchReceiver,
                    in: ctx
                )
            }
            scopeLevel = level.parent as? BaseScope
        }
        let candidates = scopeCandidates.filter { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  let signature = ctx.sema.symbols.functionSignature(for: candidate),
                  !ctx.isExpectDeclarationSupersededByActual(candidate),
                  !ctx.isImportedSymbolShadowedBySource(candidate)
            else {
                return false
            }
            return signature.receiverType == nil
                && signature.contextReceiverTypes.isEmpty
                && canBeCalledWithoutArguments(signature)
        }
        if !candidates.isEmpty {
            return safePrecheckCallResultType(candidates, in: ctx)
        }
        for candidate in scopeCandidates {
            guard let symbol = ctx.cachedSymbol(candidate) else { continue }
            let calleeType: TypeID?
            switch symbol.kind {
            case .property, .field:
                if let declared = ctx.sema.symbols.propertyType(for: candidate) {
                    calleeType = safePrecheckFlowType(
                        for: candidate,
                        fallback: declared,
                        in: ctx
                    )
                } else {
                    calleeType = nil
                }
            case .object:
                calleeType = ctx.sema.types.make(.classType(ClassType(
                    classSymbol: candidate, args: [], nullability: .nonNull
                )))
            default:
                calleeType = nil
            }
            if let calleeType {
                return safePrecheckInvokeCall(on: calleeType, in: ctx)
            }
        }
        return nil
    }

    private func precheckEffectiveClassSymbol(
        for candidate: SymbolID,
        in ctx: TypeInferenceContext
    ) -> SymbolID? {
        guard let symbol = ctx.sema.symbols.symbol(candidate) else { return nil }
        switch symbol.kind {
        case .class, .enumClass:
            return candidate
        case .typeAlias:
            guard let expanded = driver.helpers.expandTypeAlias(
                candidate,
                typeArgs: [],
                sema: ctx.sema,
                visited: [],
                depth: 0
            ), case let .classType(classType) = ctx.sema.types.kind(of: expanded)
            else {
                return nil
            }
            return classType.classSymbol
        default:
            return nil
        }
    }

    private func safePrecheckInvokeCall(
        on calleeType: TypeID,
        in ctx: TypeInferenceContext
    ) -> TypeID? {
        let receiverType = ctx.sema.types.makeNonNullable(calleeType)
        guard receiverType == calleeType else { return nil }
        if case let .functionType(functionType) = ctx.sema.types.kind(of: receiverType) {
            guard !functionType.isSuspend,
                  functionType.receiver == nil,
                  functionType.contextReceivers.isEmpty,
                  functionType.params.isEmpty,
                  isSafePrecheckValueType(functionType.returnType, in: ctx)
            else {
                return nil
            }
            return functionType.returnType
        }
        let invokeCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: ctx.interner.intern("invoke"),
            receiverType: receiverType,
            sema: ctx.sema,
            interner: ctx.interner
        ).filter { candidate in
            guard ctx.sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
                  let signature = ctx.sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.contextReceiverTypes.isEmpty
                && canBeCalledWithoutArguments(signature)
        }
        guard !invokeCandidates.isEmpty else { return nil }
        return safePrecheckCallResultType(
            invokeCandidates,
            receiverType: receiverType,
            in: ctx
        )
    }

    private func safePrecheckArrayOfCall(
        _ name: InternedString,
        typeArgs: [TypeRefID],
        args: [CallArgument],
        namedCandidates: [SymbolID],
        in ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: ctx.interner)
        guard name == ctx.interner.intern("arrayOf"),
              typeArgs.isEmpty,
              !args.isEmpty,
              args.allSatisfy({ !$0.isSpread }),
              namedCandidates.count == 1,
              let factory = ctx.sema.symbols.symbol(namedCandidates[0]),
              factory.kind == .function,
              factory.fqName == [knownNames.kotlin, name],
              let arraySymbol = ctx.sema.symbols.lookup(fqName: knownNames.kotlinArrayFQName)
        else {
            return nil
        }

        let elementTypes = args.compactMap { argument -> TypeID? in
            safePrecheckExpressionType(argument.expr, in: ctx, locals: locals)
        }
        guard elementTypes.count == args.count else { return nil }
        let elementType = ctx.sema.types.lub(elementTypes)
        guard isSafePrecheckValueType(elementType, in: ctx) else { return nil }
        return ctx.sema.types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    private func safePrecheckSafeMemberCall(
        _ exprID: ExprID,
        in ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        guard case let .safeMemberCall(receiver, name, typeArgs, args, _)? = ctx.ast.arena.expr(exprID),
              typeArgs.isEmpty,
              args.isEmpty,
              !ctx.ast.arena.isExplicitCall(exprID),
              let receiverType = safePrecheckExpressionType(receiver, in: ctx, locals: locals)
        else {
            return nil
        }
        let nonNullReceiverType = ctx.sema.types.makeNonNullable(receiverType)
        guard let property = driver.helpers.lookupMemberProperty(
            named: name,
            receiverType: nonNullReceiverType,
            sema: ctx.sema
        ), isSafePrecheckValueType(property.type, in: ctx) else {
            return nil
        }
        let resultType = ctx.sema.types.makeNullable(property.type)
        return isSafePrecheckValueType(resultType, in: ctx) ? resultType : nil
    }

    private func safePrecheckMemberCall(
        _ exprID: ExprID,
        in ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        guard case let .memberCall(receiver, name, typeArgs, args, _)? = ctx.ast.arena.expr(exprID),
              typeArgs.isEmpty,
              let receiverType = safePrecheckExpressionType(receiver, in: ctx, locals: locals)
        else {
            return nil
        }
        if args.isEmpty, !ctx.ast.arena.isExplicitCall(exprID) {
            if let property = driver.helpers.lookupMemberProperty(
                named: name,
                receiverType: receiverType,
                sema: ctx.sema
            ), isSafePrecheckValueType(property.type, in: ctx) {
                return property.type
            }
            return intrinsicArrayMemberPrecheckType(
                named: name,
                receiverType: receiverType,
                in: ctx
            )
        }

        var argumentTypes: [TypeID]? = nil
        if !args.isEmpty {
            guard args.allSatisfy({ $0.label == nil && !$0.isSpread }) else {
                return nil
            }
            var collected: [TypeID] = []
            collected.reserveCapacity(args.count)
            for argument in args {
                guard let argumentType = safePrecheckExpressionType(
                    argument.expr, in: ctx, locals: locals
                ) else {
                    return nil
                }
                collected.append(argumentType)
            }
            argumentTypes = collected
        }

        let nonNullReceiverType = ctx.sema.types.makeNonNullable(receiverType)
        let requiresInfix = ctx.ast.arena.isInfixCall(exprID)
        func isAdmissibleCandidate(_ candidate: SymbolID) -> Bool {
            !requiresInfix
                || (ctx.sema.symbols.symbol(candidate)?.flags.contains(.infixFunction) ?? false)
        }
        var candidates = driver.helpers.collectMemberFunctionCandidates(
            named: name,
            receiverType: nonNullReceiverType,
            sema: ctx.sema,
            interner: ctx.interner
        ).filter(isAdmissibleCandidate)
        candidates.append(contentsOf: safePrecheckExtensionCandidates(
            named: name,
            receiverType: nonNullReceiverType,
            argumentTypes: argumentTypes,
            in: ctx
        ).filter(isAdmissibleCandidate))
        candidates.append(contentsOf: ctx.sema.symbols.lookupByShortName(name).filter { candidate in
            isAdmissibleCandidate(candidate)
                && isSafePrecheckExtensionCandidate(
                    candidate,
                    receiverType: nonNullReceiverType,
                    argumentTypes: argumentTypes,
                    in: ctx
                )
        })
        return safePrecheckCallResultType(
            Array(Set(candidates)),
            receiverType: nonNullReceiverType,
            argumentTypes: argumentTypes,
            in: ctx
        )
    }

    private func intrinsicArrayMemberPrecheckType(
        named name: InternedString,
        receiverType: TypeID,
        in ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        guard ReceiverClassifier(sema: sema, interner: ctx.interner)
            .isArrayLikeType(sema.types.makeNonNullable(receiverType))
        else {
            return nil
        }
        switch ctx.interner.resolve(name) {
        case "size":
            return sema.types.intType
        default:
            return nil
        }
    }

    private func safePrecheckQualifiedEnumEntryType(
        _ exprID: ExprID,
        in ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        var segments: [(expr: ExprID, name: InternedString)] = []
        func collect(_ id: ExprID) -> Bool {
            switch ctx.ast.arena.expr(id) {
            case let .nameRef(name, _):
                segments.append((id, name))
                return true
            case let .memberCall(receiver, name, typeArguments, arguments, _):
                guard typeArguments.isEmpty, arguments.isEmpty,
                      !ctx.ast.arena.isExplicitCall(id), collect(receiver)
                else {
                    return false
                }
                segments.append((id, name))
                return true
            default:
                return false
            }
        }

        guard collect(exprID), segments.count >= 2,
              let root = segments.first
        else {
            return nil
        }
        guard locals[root.name] == nil else { return nil }
        for receiver in ctx.implicitReceiverMemberLookupEntries() {
            if driver.helpers.lookupMemberProperty(
                named: root.name,
                receiverType: ctx.sema.types.makeNonNullable(receiver.type),
                sema: ctx.sema
            ) != nil {
                return nil
            }
        }
        let rootCandidates = ctx.scope.lookup(root.name)
        guard rootCandidates.count == 1,
              let rootSymbol = ctx.sema.symbols.symbol(rootCandidates[0]),
              rootSymbol.kind == .class || rootSymbol.kind == .enumClass
        else {
            return nil
        }

        var ownerSymbol = rootSymbol.id
        var ownerFQName = rootSymbol.fqName
        for segment in segments.dropFirst() {
            ownerFQName.append(segment.name)
            let candidates = ctx.sema.symbols.lookupAll(fqName: ownerFQName).filter {
                ctx.sema.symbols.parentSymbol(for: $0) == ownerSymbol
            }
            guard candidates.count == 1,
                  let member = ctx.sema.symbols.symbol(candidates[0])
            else {
                return nil
            }

            if segment.expr == exprID {
                guard member.kind == .field,
                      ctx.sema.symbols.symbol(ownerSymbol)?.kind == .enumClass
                else {
                    return nil
                }
                return ctx.sema.symbols.propertyType(for: member.id)
            }

            switch member.kind {
            case .class, .interface, .object, .enumClass, .annotationClass:
                ownerSymbol = member.id
                ownerFQName = member.fqName
            default:
                return nil
            }
        }
        return nil
    }

    private func safePrecheckExtensionCandidates(
        named name: InternedString,
        receiverType: TypeID,
        argumentTypes: [TypeID]? = nil,
        in ctx: TypeInferenceContext
    ) -> [SymbolID] {
        ctx.cachedScopeLookup(name).filter { candidate in
            isSafePrecheckExtensionCandidate(
                candidate,
                receiverType: receiverType,
                argumentTypes: argumentTypes,
                in: ctx
            )
        }
    }

    private func isSafePrecheckExtensionCandidate(
        _ candidate: SymbolID,
        receiverType: TypeID,
        argumentTypes: [TypeID]? = nil,
        in ctx: TypeInferenceContext
    ) -> Bool {
        guard let symbol = ctx.sema.symbols.symbol(candidate),
              symbol.kind == .function,
              let signature = ctx.sema.symbols.functionSignature(for: candidate),
              let declaredReceiver = signature.receiverType
        else {
            return false
        }
        // A short-name symbol lookup also returns ordinary class and
        // interface members. Member dispatch already filters overridden
        // declarations, so admitting a shadowed interface member here would
        // make its return type conflict with the winning override's
        // covariant return type (KUU-3799). Keep only package-scope
        // extensions, including package extensions attached to a receiver
        // nominal while keeping their package-qualified name.
        if let parentID = ctx.sema.symbols.parentSymbol(for: candidate),
           let parent = ctx.sema.symbols.symbol(parentID),
           parent.kind != .package,
           symbol.fqName == parent.fqName + [symbol.name]
        {
            return false
        }
        guard driver.callChecker.extensionSyntheticFallbackReceiverMatches(
            callSiteReceiver: receiverType,
            declaredReceiver: declaredReceiver,
            sema: ctx.sema
        ) && signature.contextReceiverTypes.isEmpty
        else {
            return false
        }
        if let argumentTypes {
            return precheckArgumentFitsSignature(
                signature,
                candidate: candidate,
                argumentTypes: argumentTypes,
                receiverType: receiverType,
                in: ctx
            ) != nil
        }
        return canBeCalledWithoutArguments(signature)
    }

    private func safePrecheckFlowType(
        for symbol: SymbolID,
        fallback: TypeID,
        in ctx: TypeInferenceContext
    ) -> TypeID {
        guard let flow = ctx.flowState.variables[symbol],
              flow.possibleTypes.count == 1,
              let narrowedType = flow.possibleTypes.first
        else {
            return fallback
        }
        return narrowedType
    }

    private func canBeCalledWithoutArguments(_ signature: FunctionSignature) -> Bool {
        signature.parameterTypes.indices.allSatisfy { index in
            (index < signature.valueParameterHasDefaultValues.count
                && signature.valueParameterHasDefaultValues[index])
                || (index < signature.valueParameterIsVararg.count
                    && signature.valueParameterIsVararg[index])
        }
    }

    private struct PrecheckApplicableCallCandidate {
        let symbol: SymbolID
        let signature: FunctionSignature
        let boundArguments: PrecheckArgumentBindings
        let declaredParameterTypes: [TypeID]
        let argumentParameterTypes: [TypeID]
        let returnType: TypeID
        let usesVararg: Bool
    }

    private func safePrecheckCallResultType(
        _ candidates: [SymbolID],
        receiverType: TypeID? = nil,
        argumentTypes: [TypeID]? = nil,
        in ctx: TypeInferenceContext
    ) -> TypeID? {
        var resultType: TypeID?
        var sawReturnTypeDisagreement = false
        var applicableCandidates: [PrecheckApplicableCallCandidate] = []
        for candidate in Set(candidates) {
            guard let signature = ctx.sema.symbols.functionSignature(for: candidate) else {
                return nil
            }
            var boundArguments = PrecheckArgumentBindings(
                bindings: [:], substitution: [:], typeVarBySymbol: [:]
            )
            if let argumentTypes {
                guard let accepted = precheckArgumentFitsSignature(
                    signature,
                    candidate: candidate,
                    argumentTypes: argumentTypes,
                    receiverType: receiverType,
                    in: ctx
                ) else {
                    continue
                }
                boundArguments = accepted
            } else {
                guard canBeCalledWithoutArguments(signature) else {
                    return nil
                }
            }
            guard hasExplicitReturnTypeIfSourceDefined(candidate, in: ctx),
                  !signature.isSuspend,
                  signature.contextReceiverTypes.isEmpty,
                  signature.returnType != ctx.sema.types.nullableAnyType
            else {
                return nil
            }
            var candidateReturnType = specializedPrecheckMemberReturnType(
                signature.returnType,
                candidate: candidate,
                receiverType: receiverType,
                in: ctx
            )
            if argumentTypes != nil {
                candidateReturnType = ctx.sema.types.substituteTypeParameters(
                    in: candidateReturnType,
                    substitution: boundArguments.substitution,
                    typeVarBySymbol: boundArguments.typeVarBySymbol
                )
                let functionTypeParameters = Set(
                    signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount)
                )
                guard !typeUsesAnyParameter(
                    in: candidateReturnType,
                    symbols: functionTypeParameters,
                    types: ctx.sema.types
                ) else {
                    return nil
                }
            } else {
                guard !returnTypeDependsOnFunctionTypeParameters(signature, in: ctx) else {
                    return nil
                }
            }
            guard isSafePrecheckValueType(candidateReturnType, in: ctx) else {
                return nil
            }
            if let resultType, resultType != candidateReturnType {
                sawReturnTypeDisagreement = true
            } else {
                resultType = candidateReturnType
            }
            applicableCandidates.append(
                makePrecheckApplicableCallCandidate(
                    candidate,
                    signature: signature,
                    boundArguments: boundArguments,
                    returnType: candidateReturnType,
                    argumentTypes: argumentTypes,
                    receiverType: receiverType,
                    in: ctx
                )
            )
        }
        guard sawReturnTypeDisagreement else {
            return resultType
        }
        guard receiverType == nil else {
            return nil
        }
        return mostSpecificPrecheckCallResult(
            applicableCandidates,
            in: ctx
        )
    }

    private func makePrecheckApplicableCallCandidate(
        _ candidate: SymbolID,
        signature: FunctionSignature,
        boundArguments: PrecheckArgumentBindings,
        returnType: TypeID,
        argumentTypes: [TypeID]?,
        receiverType: TypeID?,
        in ctx: TypeInferenceContext
    ) -> PrecheckApplicableCallCandidate {
        let declaredParameterTypes = signature.parameterTypes.map {
            specializedPrecheckMemberReturnType(
                $0,
                candidate: candidate,
                receiverType: receiverType,
                in: ctx
            )
        }
        var argumentParameterTypes: [TypeID] = []
        if let argumentTypes {
            argumentParameterTypes.reserveCapacity(argumentTypes.count)
            for (index, _) in argumentTypes.enumerated() {
                let parameterIndex = index < declaredParameterTypes.count
                    ? index
                    : declaredParameterTypes.count - 1
                guard parameterIndex >= 0 else { continue }
                var parameterType = declaredParameterTypes[parameterIndex]
                parameterType = ctx.sema.types.substituteTypeParameters(
                    in: parameterType,
                    substitution: boundArguments.substitution,
                    typeVarBySymbol: boundArguments.typeVarBySymbol
                )
                argumentParameterTypes.append(parameterType)
            }
        }
        let parameterCount = signature.parameterTypes.count
        let lastIsVararg = parameterCount > 0
            && signature.valueParameterIsVararg.indices.contains(parameterCount - 1)
            && signature.valueParameterIsVararg[parameterCount - 1]
        let usesVararg = lastIsVararg
            && (argumentTypes?.count ?? 0) > parameterCount - 1
        return PrecheckApplicableCallCandidate(
            symbol: candidate,
            signature: signature,
            boundArguments: boundArguments,
            declaredParameterTypes: declaredParameterTypes,
            argumentParameterTypes: argumentParameterTypes,
            returnType: returnType,
            usesVararg: usesVararg
        )
    }

    private func mostSpecificPrecheckCallResult(
        _ candidates: [PrecheckApplicableCallCandidate],
        in ctx: TypeInferenceContext
    ) -> TypeID? {
        var winner: PrecheckApplicableCallCandidate?
        for candidate in candidates {
            var beatsAll = true
            for other in candidates where other.symbol != candidate.symbol {
                if !isMoreSpecificPrecheckCallCandidate(candidate, than: other, in: ctx) {
                    beatsAll = false
                    break
                }
            }
            guard beatsAll else { continue }
            if winner != nil {
                return nil
            }
            winner = candidate
        }
        return winner?.returnType
    }

    private func isMoreSpecificPrecheckCallCandidate(
        _ lhs: PrecheckApplicableCallCandidate,
        than rhs: PrecheckApplicableCallCandidate,
        in ctx: TypeInferenceContext
    ) -> Bool {
        let types = ctx.sema.types
        if precheckDeclaredShapePreferred(rhs, over: lhs, in: ctx) {
            return false
        }
        if precheckParameterListMoreSpecific(
            lhs.argumentParameterTypes,
            than: rhs.argumentParameterTypes,
            in: ctx
        ) {
            return true
        }
        if lhs.argumentParameterTypes.count == rhs.argumentParameterTypes.count,
           zip(lhs.argumentParameterTypes, rhs.argumentParameterTypes).allSatisfy({
               types.isSubtype($0, $1)
           })
        {
            let lhsCount = lhs.signature.parameterTypes.count
            let rhsCount = rhs.signature.parameterTypes.count
            if lhsCount < rhsCount {
                let boundParameters = precheckBoundParameterIndices(
                    for: rhs,
                    argumentCount: lhs.argumentParameterTypes.count
                )
                var sawUnbound = false
                var extrasOptional = true
                for index in 0..<rhsCount {
                    if boundParameters.contains(index) { continue }
                    sawUnbound = true
                    let isVararg = rhs.signature.valueParameterIsVararg.indices.contains(index)
                        && rhs.signature.valueParameterIsVararg[index]
                    let isDefaulted = rhs.signature.valueParameterHasDefaultValues.indices.contains(index)
                        && rhs.signature.valueParameterHasDefaultValues[index]
                    if !isVararg && !isDefaulted {
                        extrasOptional = false
                        break
                    }
                }
                if sawUnbound && extrasOptional {
                    return true
                }
            }
        }
        if precheckDeclaredShapePreferred(lhs, over: rhs, in: ctx) {
            return true
        }
        guard lhs.argumentParameterTypes.count == rhs.argumentParameterTypes.count,
              zip(lhs.argumentParameterTypes, rhs.argumentParameterTypes).allSatisfy({
                  types.isSubtype($0, $1) && types.isSubtype($1, $0)
              })
        else {
            return false
        }
        let lhsHasTypeParameter = precheckSignatureContainsTypeParameter(lhs.signature, in: ctx)
        let rhsHasTypeParameter = precheckSignatureContainsTypeParameter(rhs.signature, in: ctx)
        if lhsHasTypeParameter != rhsHasTypeParameter {
            return !lhsHasTypeParameter
        }
        let lhsOwnTypeParameterCount = lhs.signature.typeParameterSymbols.count
            - lhs.signature.classTypeParameterCount
        let rhsOwnTypeParameterCount = rhs.signature.typeParameterSymbols.count
            - rhs.signature.classTypeParameterCount
        if lhsOwnTypeParameterCount != rhsOwnTypeParameterCount {
            return lhsOwnTypeParameterCount < rhsOwnTypeParameterCount
        }
        if lhs.usesVararg != rhs.usesVararg {
            return !lhs.usesVararg && rhs.usesVararg
        }
        return false
    }

    private func precheckBoundParameterIndices(
        for candidate: PrecheckApplicableCallCandidate,
        argumentCount: Int
    ) -> Set<Int> {
        let parameterCount = candidate.signature.parameterTypes.count
        guard parameterCount > 0 else { return [] }
        var indices: Set<Int> = []
        indices.reserveCapacity(min(argumentCount, parameterCount))
        for index in 0..<argumentCount {
            indices.insert(min(index, parameterCount - 1))
        }
        return indices
    }

    private func precheckParameterListMoreSpecific(
        _ lhs: [TypeID],
        than rhs: [TypeID],
        in ctx: TypeInferenceContext
    ) -> Bool {
        let types = ctx.sema.types
        guard lhs.count == rhs.count else { return false }
        var sawStrict = false
        for (lhsParam, rhsParam) in zip(lhs, rhs) {
            guard types.isSubtype(lhsParam, rhsParam) else { return false }
            if !types.isSubtype(rhsParam, lhsParam) {
                sawStrict = true
            }
        }
        return sawStrict
    }

    private func precheckDeclaredShapePreferred(
        _ lhs: PrecheckApplicableCallCandidate,
        over rhs: PrecheckApplicableCallCandidate,
        in ctx: TypeInferenceContext
    ) -> Bool {
        let types = ctx.sema.types
        let lhsDeclared = lhs.declaredParameterTypes
        let rhsDeclared = rhs.declaredParameterTypes
        guard lhsDeclared.count == rhsDeclared.count, !lhsDeclared.isEmpty else {
            return false
        }
        func isBareTypeParameter(_ type: TypeID) -> Bool {
            if case .typeParam = types.kind(of: types.makeNonNullable(type)) {
                return true
            }
            return false
        }
        var sawStrict = false
        for (l, r) in zip(lhsDeclared, rhsDeclared) {
            let lBare = isBareTypeParameter(l)
            let rBare = isBareTypeParameter(r)
            if rBare, !lBare {
                sawStrict = true
            } else if lBare != rBare {
                return false
            } else if !lBare, l != r {
                return false
            }
        }
        return sawStrict
    }

    private func precheckSignatureContainsTypeParameter(
        _ signature: FunctionSignature,
        in ctx: TypeInferenceContext
    ) -> Bool {
        let symbols = Set(signature.typeParameterSymbols)
        guard !symbols.isEmpty else { return false }
        let types = ctx.sema.types
        for parameterType in signature.parameterTypes {
            if typeUsesAnyParameter(in: parameterType, symbols: symbols, types: types) {
                return true
            }
        }
        if let receiverType = signature.receiverType,
           typeUsesAnyParameter(in: receiverType, symbols: symbols, types: types)
        {
            return true
        }
        return false
    }

    private struct PrecheckArgumentBindings {
        var bindings: [SymbolID: TypeID]
        var substitution: [TypeVarID: TypeID]
        var typeVarBySymbol: [SymbolID: TypeVarID]
    }

    private func precheckArgumentFitsSignature(
        _ signature: FunctionSignature,
        candidate: SymbolID,
        argumentTypes: [TypeID],
        receiverType: TypeID?,
        bindableTypeParameters: Set<SymbolID>? = nil,
        in ctx: TypeInferenceContext
    ) -> PrecheckArgumentBindings? {
        let types = ctx.sema.types
        let parameterCount = signature.parameterTypes.count
        func isVararg(_ index: Int) -> Bool {
            index < signature.valueParameterIsVararg.count
                && signature.valueParameterIsVararg[index]
        }
        if argumentTypes.count < parameterCount {
            for index in argumentTypes.count..<parameterCount {
                let defaulted = index < signature.valueParameterHasDefaultValues.count
                    && signature.valueParameterHasDefaultValues[index]
                guard defaulted || isVararg(index) else { return nil }
            }
        } else if argumentTypes.count > parameterCount {
            guard parameterCount > 0, isVararg(parameterCount - 1) else { return nil }
        }

        let typeParameterSet = bindableTypeParameters ?? Set(
            signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount)
        )
        let typeVarBySymbol = types.makeTypeVarBySymbol(Array(typeParameterSet))
        var bindings: [SymbolID: TypeID] = [:]
        var substitution: [TypeVarID: TypeID] = [:]

        for (index, argumentType) in argumentTypes.enumerated() {
            let parameterIndex = index < parameterCount ? index : parameterCount - 1
            guard parameterIndex >= 0 else { return nil }
            let parameterType = specializedPrecheckMemberReturnType(
                signature.parameterTypes[parameterIndex],
                candidate: candidate,
                receiverType: receiverType,
                in: ctx
            )
            if case let .typeParam(typeParam) = types.kind(of: types.makeNonNullable(parameterType)),
               typeParameterSet.contains(typeParam.symbol)
            {
                guard precheckArgumentRespectsTypeParameterBounds(
                    argumentType,
                    typeParameterSymbol: typeParam.symbol,
                    candidate: candidate,
                    receiverType: receiverType,
                    boundTypeParameters: typeParameterSet,
                    in: ctx
                ) else {
                    return nil
                }
                let boundType = bindings[typeParam.symbol].map {
                    types.lub([$0, argumentType])
                } ?? argumentType
                bindings[typeParam.symbol] = boundType
                if let typeVar = typeVarBySymbol[typeParam.symbol] {
                    substitution[typeVar] = boundType
                }
                continue
            }
            if typeUsesAnyParameter(
                in: parameterType,
                symbols: typeParameterSet,
                types: types
            ) {
                return nil
            }
            guard types.isSubtype(argumentType, parameterType) else {
                return nil
            }
        }
        return PrecheckArgumentBindings(
            bindings: bindings,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    private func precheckArgumentRespectsTypeParameterBounds(
        _ argumentType: TypeID,
        typeParameterSymbol: SymbolID,
        candidate: SymbolID,
        receiverType: TypeID?,
        boundTypeParameters: Set<SymbolID>,
        in ctx: TypeInferenceContext
    ) -> Bool {
        for bound in ctx.sema.symbols.typeParameterUpperBounds(for: typeParameterSymbol) {
            let resolvedBound = specializedPrecheckMemberReturnType(
                bound,
                candidate: candidate,
                receiverType: receiverType,
                in: ctx
            )
            if typeUsesAnyParameter(
                in: resolvedBound,
                symbols: boundTypeParameters,
                types: ctx.sema.types
            ) || !ctx.sema.types.isSubtype(argumentType, resolvedBound)
            {
                return false
            }
        }
        return true
    }

    private func specializedPrecheckMemberReturnType(
        _ returnType: TypeID,
        candidate: SymbolID,
        receiverType: TypeID?,
        in ctx: TypeInferenceContext
    ) -> TypeID {
        guard let receiverType,
              ctx.sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
              let owner = ctx.sema.symbols.parentSymbol(for: candidate),
              case let .classType(classType) = ctx.sema.types.kind(
                  of: ctx.sema.types.makeNonNullable(receiverType)
              ),
              ctx.sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: owner),
              let ownerTypeArgs = ctx.sema.types.liftedNominalSupertypeArgs(
                  from: classType,
                  to: owner
              )
        else {
            return returnType
        }
        let ownerTypeParameters = ctx.sema.types.allTypeParameterSymbols(for: owner)
        guard !ownerTypeParameters.isEmpty else {
            return returnType
        }
        let typeVarBySymbol = ctx.sema.types.makeTypeVarBySymbol(ownerTypeParameters)
        var substitution: [TypeVarID: TypeID] = [:]
        for (index, typeParameter) in ownerTypeParameters.enumerated() {
            guard index < ownerTypeArgs.count,
                  let typeVar = typeVarBySymbol[typeParameter]
            else {
                continue
            }
            switch ownerTypeArgs[index] {
            case let .invariant(inner), let .out(inner), let .in(inner):
                substitution[typeVar] = inner
            case .star:
                substitution[typeVar] = ctx.sema.types.nullableAnyType
            }
        }
        guard !substitution.isEmpty else {
            return returnType
        }
        return ctx.sema.types.substituteTypeParameters(
            in: returnType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    private func hasExplicitReturnTypeIfSourceDefined(
        _ candidate: SymbolID,
        in ctx: TypeInferenceContext
    ) -> Bool {
        for declID in ctx.ast.activeDeclarationIDs
            where ctx.sema.bindings.declSymbols[declID] == candidate
        {
            guard case let .funDecl(function)? = ctx.ast.arena.decl(declID) else {
                return false
            }
            return function.returnType != nil
        }
        return true
    }

    private func returnTypeDependsOnFunctionTypeParameters(
        _ signature: FunctionSignature,
        in ctx: TypeInferenceContext
    ) -> Bool {
        let functionTypeParameters = Set(
            signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount)
        )
        guard !functionTypeParameters.isEmpty else { return false }
        return typeUsesAnyParameter(
            in: signature.returnType,
            symbols: functionTypeParameters,
            types: ctx.sema.types
        )
    }

    private func typeUsesAnyParameter(
        in type: TypeID,
        symbols: Set<SymbolID>,
        types: TypeSystem
    ) -> Bool {
        switch types.kind(of: types.makeNonNullable(type)) {
        case let .typeParam(typeParam):
            symbols.contains(typeParam.symbol)
        case let .classType(classType):
            classType.args.contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    typeUsesAnyParameter(in: inner, symbols: symbols, types: types)
                case .star:
                    false
                }
            }
        case let .functionType(functionType):
            (functionType.receiver.map {
                typeUsesAnyParameter(in: $0, symbols: symbols, types: types)
            } ?? false)
                || functionType.params.contains {
                    typeUsesAnyParameter(in: $0, symbols: symbols, types: types)
                }
                || typeUsesAnyParameter(in: functionType.returnType, symbols: symbols, types: types)
                || functionType.contextReceivers.contains {
                    typeUsesAnyParameter(in: $0, symbols: symbols, types: types)
                }
        case let .kClassType(kClassType):
            typeUsesAnyParameter(in: kClassType.argument, symbols: symbols, types: types)
        case let .intersection(parts):
            parts.contains { typeUsesAnyParameter(in: $0, symbols: symbols, types: types) }
        default:
            false
        }
    }

    private func safePrecheckBinaryType(
        _ op: BinaryOp,
        lhs: ExprID,
        rhs: ExprID,
        in ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        let types = ctx.sema.types
        if op == .logicalAnd || op == .logicalOr {
            guard let lhsType = safePrecheckExpressionType(lhs, in: ctx, locals: locals),
                  lhsType == types.booleanType
            else {
                return nil
            }
            let branch = ctx.dataFlow.branchOnCondition(
                lhs,
                base: ctx.flowState.includingMembers(from: locals),
                locals: locals,
                ast: ctx.ast,
                sema: ctx.sema,
                interner: ctx.interner,
                scope: ctx.scope
            )
            var rhsState = op == .logicalAnd ? branch.trueState : branch.falseState
            if op == .logicalAnd,
               case let .isCheck(subject, targetTypeRef, false, _)? = ctx.ast.arena.expr(lhs),
               let subjectSymbol = safePrecheckReferenceSymbol(subject, in: ctx, locals: locals),
               let targetType = safePrecheckTypeRef(targetTypeRef, in: ctx)
            {
                rhsState.variables[subjectSymbol] = VariableFlowState(
                    possibleTypes: [targetType],
                    nullability: types.nullability(of: targetType),
                    isStable: true
                )
            }
            var rhsLocals = locals
            driver.exprChecker.applyFlowStateToLocals(
                rhsState,
                locals: &rhsLocals,
                sema: ctx.sema
            )
            guard let rhsType = safePrecheckExpressionType(
                rhs,
                in: ctx.copying(flowState: rhsState),
                locals: rhsLocals
            ), rhsType == types.booleanType
            else {
                return nil
            }
            return types.booleanType
        }
        guard let lhsType = safePrecheckExpressionType(lhs, in: ctx, locals: locals),
              let rhsType = safePrecheckExpressionType(rhs, in: ctx, locals: locals)
        else {
            return nil
        }

        switch op {
        case .equal, .notEqual:
            if isNullLiteral(lhs, in: ctx) || isNullLiteral(rhs, in: ctx) {
                return types.booleanType
            }
            return lhsType == rhsType && isSafeEqualityType(lhsType, in: ctx)
                ? types.booleanType : nil
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            return lhsType == rhsType && isSafeComparableType(lhsType, in: ctx)
                ? types.booleanType : nil
        case .add:
            if lhsType == types.stringType {
                return isSafePrecheckValueType(rhsType, in: ctx) ? types.stringType : nil
            }
            return safePrecheckNumericBinaryType(op, lhs: lhsType, rhs: rhsType, in: ctx)
        case .subtract, .multiply, .divide, .modulo:
            return safePrecheckNumericBinaryType(op, lhs: lhsType, rhs: rhsType, in: ctx)
        case .elvis:
            let result = types.lub([
                types.definitelyNonNullForm(of: lhsType),
                rhsType,
            ])
            return isSafePrecheckValueType(result, in: ctx) ? result : nil
        default:
            return nil
        }
    }

    private func safePrecheckReferenceSymbol(
        _ exprID: ExprID,
        in ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> SymbolID? {
        guard let expr = ctx.ast.arena.expr(exprID) else { return nil }
        switch expr {
        case let .nameRef(name, _):
            if let local = locals[name] {
                return local.symbol
            }
            let candidates = ctx.scope.lookup(name)
            guard candidates.count == 1,
                  let symbol = ctx.sema.symbols.symbol(candidates[0]),
                  symbol.kind == .property || symbol.kind == .field
            else {
                return nil
            }
            return candidates[0]
        case let .memberCall(receiver, name, typeArgs, args, _)
            where typeArgs.isEmpty && args.isEmpty && !ctx.ast.arena.isExplicitCall(exprID):
            guard let receiverType = safePrecheckExpressionType(receiver, in: ctx, locals: locals) else {
                return nil
            }
            return driver.helpers.lookupMemberProperty(
                named: name,
                receiverType: receiverType,
                sema: ctx.sema
            )?.symbol
        default:
            return nil
        }
    }

    private func safePrecheckTypeRef(
        _ typeRef: TypeRefID,
        in ctx: TypeInferenceContext
    ) -> TypeID? {
        let type = driver.helpers.resolveTypeRef(
            typeRef,
            ast: ctx.ast,
            sema: ctx.sema,
            interner: ctx.interner,
            scope: ctx.scope,
            inferenceContext: ctx
        )
        return type == ctx.sema.types.errorType ? nil : type
    }

    private func isSafePrecheckValueType(_ type: TypeID, in ctx: TypeInferenceContext) -> Bool {
        guard type != ctx.sema.types.errorType,
              type != ctx.sema.types.nullableAnyType
        else {
            return false
        }
        switch ctx.sema.types.kind(of: type) {
        case .primitive, .stringStruct, .classType, .typeParam, .any(.nonNull):
            return true
        case .error, .unit, .nullableUnit, .platformUnit, .nothing, .any(.nullable), .any(.platformType),
             .functionType, .intersection, .kClassType:
            return false
        }
    }

    private func isSafeNumericType(_ type: TypeID, in ctx: TypeInferenceContext) -> Bool {
        guard case let .primitive(primitive, .nonNull) = ctx.sema.types.kind(of: type) else {
            return false
        }
        switch primitive {
        case .int, .long, .float, .double, .uint, .ulong, .ubyte, .ushort, .byte, .short:
            return true
        case .boolean, .char:
            return false
        }
    }

    private func isSafeEqualityType(_ type: TypeID, in ctx: TypeInferenceContext) -> Bool {
        type == ctx.sema.types.stringType
            || type == ctx.sema.types.booleanType
            || type == ctx.sema.types.charType
            || isSafeNumericType(type, in: ctx)
    }

    private func isSafeComparableType(_ type: TypeID, in ctx: TypeInferenceContext) -> Bool {
        isSafeNumericType(type, in: ctx) || type == ctx.sema.types.charType
    }

    private func isNullLiteral(_ exprID: ExprID, in ctx: TypeInferenceContext) -> Bool {
        if case .nullLiteral? = ctx.ast.arena.expr(exprID) {
            return true
        }
        return false
    }

    private func safePrecheckNumericBinaryType(
        _ op: BinaryOp,
        lhs: TypeID,
        rhs: TypeID,
        in ctx: TypeInferenceContext
    ) -> TypeID? {
        let types = ctx.sema.types
        let signedTypes: Set<TypeID> = [types.byteType, types.shortType, types.intType, types.longType]
        let unsignedTypes: Set<TypeID> = [types.ubyteType, types.ushortType, types.uintType, types.ulongType]
        guard isSafeNumericType(lhs, in: ctx), isSafeNumericType(rhs, in: ctx),
              !((signedTypes.contains(lhs) && unsignedTypes.contains(rhs))
                  || (unsignedTypes.contains(lhs) && signedTypes.contains(rhs)))
        else {
            return nil
        }

        switch op {
        case .add, .subtract, .multiply, .divide, .modulo:
            if lhs == types.doubleType || rhs == types.doubleType {
                return types.doubleType
            }
            if lhs == types.floatType || rhs == types.floatType {
                return types.floatType
            }
            if lhs == types.longType || rhs == types.longType {
                return types.longType
            }
            if lhs == types.ulongType || rhs == types.ulongType {
                return types.ulongType
            }
            if unsignedTypes.contains(lhs) || unsignedTypes.contains(rhs) {
                return types.uintType
            }
            return types.intType
        default:
            return nil
        }
    }
}
