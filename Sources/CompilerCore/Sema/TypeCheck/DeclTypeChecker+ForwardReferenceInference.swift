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
        // Match the header pass's generic receiver: member property initializers
        // and accessors need C<T>, not the raw class type C.
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
        // Keep the class receiver addressable to nested lambdas that use `this@Class`.
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
        // Property initializers run with the class receiver but do not pass
        // through the member-function local-binding setup. Give `this` the
        // same synthetic receiver identity so data-flow narrowing (for
        // example, `this is Subtype`) is visible inside initializer branches.
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
        // Use the same receiver and visibility scope as the authoritative pass.
        // Companion initializers must not inherit constructor parameter locals.
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
        diagnostics: DiagnosticEngine
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

        // Revisit member properties until their dependencies resolve. Calls and
        // member reads are eligible only when their referenced signatures or
        // property types are already concrete; inferred-return calls and cycles
        // stay on the normal pass.
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
                if canSafelyPrecheckInferredProperty(
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
                    // Publish only the inferred type; diagnostics belong to the
                    // authoritative pass, which re-emits them in source order.
                    diagnostics.truncate(to: diagnosticSnapshot)
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
            }
        } while didPrecheckProperty
    }

    /// A `var` with a real custom setter cannot run its bound declaration
    /// check early — the setter body may reference declarations that are only
    /// checked later — but its property type comes solely from the
    /// initializer. When that initializer is safe to precheck, publish just
    /// the inferred type so earlier bodies see the concrete type; the
    /// authoritative declaration pass still rechecks the whole property,
    /// including the accessors (KUU-3799).
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
        let diagnosticSnapshot = ctx.sema.diagnostics.count
        defer { ctx.sema.diagnostics.truncate(to: diagnosticSnapshot) }
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
        precheckIndependentMemberProperties(
            memberProperties,
            ctx: ctx,
            initialLocals: initialLocals,
            solver: solver,
            diagnostics: diagnostics
        )
    }

    func canSafelyPrecheckInferredProperty(
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

        // Make a simple inferred extension getter's receiver available during
        // prechecking so earlier function bodies see its concrete return type.
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

        // A non-extension `val x get() = ...` derives its type from the getter
        // body — the same inference the declaration pass performs in source
        // order. When that body is safe to precheck, let the property publish
        // its type before earlier declarations observe the placeholder
        // (KUU-3912).
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

        // A visibility-only setter such as `internal set` has no body and does
        // not change the initializer's inferred property type.
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

    /// An inferred property with a custom accessor body still derives its type
    /// from a safe initializer — the accessor bodies only constrain that type,
    /// they cannot replace it. Such a property may publish its inferred type
    /// ahead of source order so earlier declarations see the concrete type
    /// instead of the nullable-Any placeholder; the accessor bodies themselves
    /// stay on the source-order pass, which re-checks the whole declaration.
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
            // `this` names the innermost implicit receiver; `this@Label`
            // names an outer one. Both feed explicit member reads such as
            // `this.makeInt()` in a property initializer.
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
        default:
            // Arbitrary control flow, mutation, and delegates are deliberately
            // left on the normal declaration-order path.
            return nil
        }
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
            ) {
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
        if symbol.kind == .object {
            // Singleton receivers already have a nominal type from their header.
            // Their member reads still wait for concrete property types below.
            if symbol.id == ctx.sema.types.unitClassSymbol {
                return ctx.sema.types.unitType
            }
            return ctx.sema.symbols.propertyType(for: symbol.id)
                ?? ctx.sema.types.make(.classType(ClassType(
                    classSymbol: symbol.id, args: [], nullability: .nonNull
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
        if namedCandidates.count == 1,
           let symbol = ctx.sema.symbols.symbol(namedCandidates[0]),
           symbol.kind == .class || symbol.kind == .enumClass,
           args.allSatisfy({ safePrecheckExpressionType($0.expr, in: ctx, locals: locals) != nil })
        {
            // Every constructor of this non-generic class returns the same
            // header-resolved type. The property checker still resolves the
            // overload and validates argument types and visibility once.
            if typeArgs.isEmpty && ctx.sema.types.nominalTypeParameterSymbols(for: symbol.id).isEmpty {
                return ctx.sema.types.make(.classType(ClassType(
                    classSymbol: symbol.id, args: [], nullability: .nonNull
                )))
            }
            // Argument values can also pin a generic class's parameters when
            // every applicable constructor binds the same class type
            // arguments — `Pair("k", 1)` is `Pair<String, Int>` regardless of
            // which `Pair` ctor overload resolution would pick. Constructors
            // whose parameters mention a nested or unbound type parameter, or
            // that disagree on the result, stay on the normal pass (KUU-3912).
            let typeParameters = ctx.sema.types.nominalTypeParameterSymbols(for: symbol.id)
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
            // An explicit argument list pins a generic class's parameters, so
            // a companion singleton such as `Node<Nothing, Nothing>(0)` is as
            // safe to infer early as a non-generic constructor call. Default
            // parameters may still read placeholder types; require every
            // constructor to declare all of its parameters.
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
        // Calls with positional arguments — `listOf("")`, `makeToken(seed)` —
        // are stable when every argument has a safe type and the surviving
        // overloads agree on a concrete return type. Bare type parameters in
        // the parameter list bind to the least upper bound of the arguments,
        // which keeps single-parameter factories resolvable (KUU-3912).
        if !args.isEmpty {
            guard args.allSatisfy({ $0.label == nil && !$0.isSpread }) else {
                return nil
            }
            // A member on an implicit receiver shadows lexical functions, but
            // this branch only weighs receiver-less candidates. Leave such
            // calls to the normal resolver instead of picking a top-level
            // overload the member would hide.
            for receiver in ctx.implicitReceiverMemberLookupEntries() {
                let receiverType = ctx.sema.types.makeNonNullable(receiver.type)
                if !driver.helpers.collectMemberFunctionCandidates(
                    named: name,
                    receiverType: receiverType,
                    sema: ctx.sema,
                    interner: ctx.interner
                ).isEmpty || driver.helpers.lookupMemberProperty(
                    named: name,
                    receiverType: receiver.type,
                    sema: ctx.sema
                ) != nil {
                    return nil
                }
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
            let candidates = namedCandidates.filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      let signature = ctx.sema.symbols.functionSignature(for: candidate),
                      !ctx.isExpectDeclarationSupersededByActual(candidate),
                      !ctx.isImportedCallableShadowedBySource(candidate)
                else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.contextReceiverTypes.isEmpty
            }
            return safePrecheckCallResultType(
                candidates,
                argumentTypes: argumentTypes,
                in: ctx
            )
        }

        // An unqualified call inside a class or object can resolve to a
        // member function on an implicit receiver (`val x = makeInt()`).
        // Member signatures store their dispatch receiver in
        // `signature.receiverType`, so the lexical filter below rejects them
        // even though the enclosing receiver satisfies the call. Walk the
        // receiver tower like `safePrecheckNameReference` does: the nearest
        // receiver exposing an applicable member wins over lexical
        // candidates, matching the normal call resolver's ordering.
        for receiver in ctx.implicitReceiverMemberLookupEntries() {
            let receiverType = ctx.sema.types.makeNonNullable(receiver.type)
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: name,
                receiverType: receiverType,
                sema: ctx.sema,
                interner: ctx.interner
            ).filter { candidate in
                // Member extensions still need a separate extension receiver
                // the unqualified call cannot supply.
                guard ctx.sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
                      let signature = ctx.sema.symbols.functionSignature(for: candidate)
                else {
                    return false
                }
                return signature.contextReceiverTypes.isEmpty
                    && canBeCalledWithoutArguments(signature)
            }
            // An inapplicable member does not stop resolution: the call
            // continues to outer receivers and the lexical scope.
            if !memberCandidates.isEmpty {
                return safePrecheckCallResultType(
                    memberCandidates,
                    receiverType: receiverType,
                    in: ctx
                )
            }
            // A member property named `name` still binds the callee at this
            // receiver: `name()` can only resolve through `invoke` on the
            // property's type — or not at all. Either way the member shadows
            // outer scopes, so the search stops rather than falling through
            // to a same-named top-level function.
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

        // The receiver tower covered the implicit-receiver member scopes,
        // but `scope.lookup` still stops at the innermost level binding
        // `name` — including member tiers the tower cannot see, such as the
        // companion-object scope. Walk the chain so those members get their
        // turn: a level binding `name` only to member functions yields them
        // as implicit-dispatch candidates; when none apply, the call
        // continues to the next level instead of being shadowed by an
        // inapplicable member. Any other binding kind (a same-named
        // property or classifier) keeps its normal shadowing.
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
                // A receiver-typed function at a lexical tier is callable
                // only when an implicit receiver supplies its dispatch
                // receiver — the enclosing nominal or one of its companion
                // objects. This keeps a same-named extension on an unrelated
                // type (e.g. `fun String.f()` at package scope) from being
                // treated as applicable here.
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
                  !ctx.isImportedCallableShadowedBySource(candidate)
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
        // The tier that stopped the walk bound `name` only to non-function
        // declarations. A property or object there can still answer `name()`
        // through `invoke`; a binding that cannot produce one shadows the
        // outer scopes all the same, so the first bound value ends the search.
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

    /// `callee()` on a property or object resolves through `invoke` on its
    /// type. Function-typed callees answer with their declared return type —
    /// their `invoke` has no nominal member to collect — while nominal
    /// callees resolve `invoke` like any other zero-argument member call.
    private func safePrecheckInvokeCall(
        on calleeType: TypeID,
        in ctx: TypeInferenceContext
    ) -> TypeID? {
        let receiverType = ctx.sema.types.makeNonNullable(calleeType)
        // Only a non-nullable callee can be invoked without `?.`.
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
            // A member or top-level `invoke` extension still needs the
            // extension receiver the unqualified call cannot supply.
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

        // A non-empty arrayOf call has a stable element LUB when each argument
        // is independently safe to type-check before its declaration body.
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
            guard let property = driver.helpers.lookupMemberProperty(
                named: name,
                receiverType: receiverType,
                sema: ctx.sema
            ), isSafePrecheckValueType(property.type, in: ctx)
            else {
                return nil
            }
            return property.type
        }

        // Calls with arguments — `x.f(y)`, infix `x or y` — are also stable
        // when every positional argument has a safe type and the surviving
        // candidates agree on a concrete return type. Labeled arguments can
        // reorder parameters and spreads carry whole arrays, so they stay on
        // the normal pass (KUU-3912).
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
        // Kotlin requires the `infix` modifier for `a op b` calls, so an
        // infix-shaped call only admits candidates carrying the flag.
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
        // Bundled source extensions are not always present in the lexical
        // scope (the regular member-call resolver also falls back to the
        // symbol table by short name for these declarations).
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

    /// Enum-entry initializers can appear as a classifier-qualified chain
    /// such as `Parser.ValueOrigin.UNSET`. The ordinary member-call precheck
    /// treats the first classifier as a value receiver, so it cannot infer
    /// this chain and leaves an enclosing inferred property at its `Any?`
    /// header type.
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

    private func safePrecheckCallResultType(
        _ candidates: [SymbolID],
        receiverType: TypeID? = nil,
        argumentTypes: [TypeID]? = nil,
        in ctx: TypeInferenceContext
    ) -> TypeID? {
        var resultType: TypeID?
        for candidate in Set(candidates) {
            guard let signature = ctx.sema.symbols.functionSignature(for: candidate) else {
                return nil
            }
            var boundArguments = PrecheckArgumentBindings(
                bindings: [:], substitution: [:], typeVarBySymbol: [:]
            )
            if let argumentTypes {
                // Overload resolution discards candidates that cannot accept
                // the arguments, so inapplicable ones do not veto the result.
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
                // A surviving function type parameter means the arguments could
                // not pin the result (e.g. `listOf()`): stay conservative.
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
                // Without resolving an overload, only accept a result type that
                // is the same for every applicable candidate.
                return nil
            }
            resultType = candidateReturnType
        }
        return resultType
    }

    /// Substitution bindings collected while checking that positional
    /// arguments fit a candidate signature. `bindings` keeps the resolved
    /// type per type-parameter symbol so class-level parameters can become
    /// constructor type arguments; `substitution`/`typeVarBySymbol` drive
    /// `substituteTypeParameters` on the result type.
    private struct PrecheckArgumentBindings {
        var bindings: [SymbolID: TypeID]
        var substitution: [TypeVarID: TypeID]
        var typeVarBySymbol: [SymbolID: TypeVarID]
    }

    /// Positional argument fitting for a candidate call: arity must satisfy
    /// the parameter list (a defaulted or vararg tail may absorb the
    /// difference), each concrete parameter type must accept its argument as a
    /// subtype, and a bare function type parameter accumulates a
    /// least-upper-bound binding so factories like `listOf(x)` can pin `T`.
    /// Anything unverifiable — nested type parameters in a parameter or an
    /// upper bound — returns nil and keeps the expression on the normal pass
    /// (KUU-3912).
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
                // `Pair<K, V>`-style parameters need real constraint solving.
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

    /// A bare `T` parameter may only bind an argument inside `T`'s declared
    /// upper bounds. Bounds still mentioning another function type parameter
    /// cannot be checked here, so they reject the binding conservatively.
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

    /// A member signature's return type is stored in terms of the declaring
    /// owner's type parameters. Substitute the call-site receiver's lifted
    /// supertype arguments so `map.hashMap.builder()` on
    /// `PersistentHashMap<K, LinkedValue<V>>` yields
    /// `PersistentHashMapBuilder<K, LinkedValue<V>>` rather than the
    /// owner's raw `PersistentHashMapBuilder<K, V>` (KUU-3799).
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
        // Precompiled stdlib and dependency symbols already carry a resolved
        // signature and have no source declaration in this AST.
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
                // Header-time bindings for implicit member properties do not
                // yet exist, so DataFlowAnalyzer cannot identify this stable
                // reference. Mirror the positive `is` refinement from the AST
                // for the right-hand side of `&&`.
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
