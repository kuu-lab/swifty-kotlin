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
        let primaryConstructorLocals = primaryConstructorParameterLocals(
            classDecl: classDecl,
            ctx: classContext
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
                      let propertySymbol = sema.bindings.declSymbols[declID],
                      canSafelyPrecheckInferredProperty(
                          property,
                          symbol: propertySymbol,
                          in: ctx,
                          initialLocals: initialLocals
                      )
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
                didPrecheckProperty = true
            }
        } while didPrecheckProperty
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
              property.setter == nil,
              property.explicitBackingField == nil
        else {
            return false
        }

        // Make a simple inferred extension getter's receiver available during
        // prechecking so earlier function bodies see its concrete return type.
        if let receiverType = ctx.sema.symbols.extensionPropertyReceiverType(for: symbol) {
            guard !property.isVar,
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

        guard property.getter == nil,
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
            // An explicit argument list pins a generic class's parameters, so
            // a companion singleton such as `Node<Nothing, Nothing>(0)` is as
            // safe to infer early as a non-generic constructor call. Default
            // parameters may still read placeholder types; require every
            // constructor to declare all of its parameters.
            let typeParameters = ctx.sema.types.nominalTypeParameterSymbols(for: symbol.id)
            let initName = ctx.interner.intern("<init>")
            let constructorSymbols = ctx.sema.symbols.lookupAll(fqName: symbol.fqName + [initName])
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
        guard args.isEmpty, typeArgs.isEmpty else { return nil }
        let candidates = namedCandidates.filter { candidate in
            guard let symbol = ctx.sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  let signature = ctx.sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.receiverType == nil
                && signature.contextReceiverTypes.isEmpty
                && canBeCalledWithoutArguments(signature)
        }
        return safePrecheckCallResultType(candidates, in: ctx)
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
              args.isEmpty,
              let receiverType = safePrecheckExpressionType(receiver, in: ctx, locals: locals)
        else {
            return nil
        }
        if !ctx.ast.arena.isExplicitCall(exprID) {
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

        let nonNullReceiverType = ctx.sema.types.makeNonNullable(receiverType)
        var candidates = driver.helpers.collectMemberFunctionCandidates(
            named: name,
            receiverType: nonNullReceiverType,
            sema: ctx.sema,
            interner: ctx.interner
        )
        candidates.append(contentsOf: safePrecheckExtensionCandidates(
            named: name,
            receiverType: nonNullReceiverType,
            in: ctx
        ))
        // Bundled source extensions are not always present in the lexical
        // scope (the regular member-call resolver also falls back to the
        // symbol table by short name for these declarations).
        candidates.append(contentsOf: ctx.sema.symbols.lookupByShortName(name).filter { candidate in
            isSafePrecheckExtensionCandidate(
                candidate,
                receiverType: nonNullReceiverType,
                in: ctx
            )
        })
        return safePrecheckCallResultType(Array(Set(candidates)), in: ctx)
    }

    private func safePrecheckExtensionCandidates(
        named name: InternedString,
        receiverType: TypeID,
        in ctx: TypeInferenceContext
    ) -> [SymbolID] {
        ctx.cachedScopeLookup(name).filter { candidate in
            isSafePrecheckExtensionCandidate(candidate, receiverType: receiverType, in: ctx)
        }
    }

    private func isSafePrecheckExtensionCandidate(
        _ candidate: SymbolID,
        receiverType: TypeID,
        in ctx: TypeInferenceContext
    ) -> Bool {
        guard let symbol = ctx.sema.symbols.symbol(candidate),
              symbol.kind == .function,
              let signature = ctx.sema.symbols.functionSignature(for: candidate),
              let declaredReceiver = signature.receiverType
        else {
            return false
        }
        return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
            callSiteReceiver: receiverType,
            declaredReceiver: declaredReceiver,
            sema: ctx.sema
        ) && signature.contextReceiverTypes.isEmpty
            && canBeCalledWithoutArguments(signature)
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
        in ctx: TypeInferenceContext
    ) -> TypeID? {
        var resultType: TypeID?
        for candidate in Set(candidates) {
            guard let signature = ctx.sema.symbols.functionSignature(for: candidate),
                  hasExplicitReturnTypeIfSourceDefined(candidate, in: ctx),
                  !signature.isSuspend,
                  signature.contextReceiverTypes.isEmpty,
                  canBeCalledWithoutArguments(signature),
                  signature.returnType != ctx.sema.types.nullableAnyType,
                  isSafePrecheckValueType(signature.returnType, in: ctx),
                  !returnTypeDependsOnFunctionTypeParameters(signature, in: ctx)
            else {
                return nil
            }
            if let resultType, resultType != signature.returnType {
                // Without resolving an overload, only accept a result type that
                // is the same for every zero-argument candidate.
                return nil
            }
            resultType = signature.returnType
        }
        return resultType
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
        case .add, .subtract:
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
        case .multiply, .divide, .modulo:
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
