extension DeclTypeChecker {
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
        let classContext = ctx.withoutSuspensionContext()
            .withOuterReceiver(label: classLabel, type: classType)
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
        let sema = ctx.sema

        // Literal properties are independent of other declarations. Resolve
        // them first so a lazy Boolean property can safely depend on one.
        for declID in classDecl.memberProperties {
            guard let decl = ctx.ast.arena.decl(declID),
                  case let .propertyDecl(property) = decl,
                  hasIndependentBooleanInitializer(property, ast: ctx.ast),
                  let propertySymbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            typeCheckBoundPropertyDecl(
                property,
                declID: declID,
                symbol: propertySymbol,
                ctx: classContext.with(currentDeclSymbol: propertySymbol),
                initialLocals: primaryConstructorLocals,
                solver: solver,
                diagnostics: diagnostics
            )
            driver.precheckedPropertyDecls.insert(declID)
        }

        // A lazy property's type comes from its lambda body. Pre-check only
        // simple Boolean expressions whose property references already have a
        // concrete header or prechecked type. Calls and unresolved references
        // stay in declaration order, preserving inferred-function and cycle
        // diagnostics instead of speculatively checking them twice.
        for declID in classDecl.memberProperties {
            guard let decl = ctx.ast.arena.decl(declID),
                  case let .propertyDecl(property) = decl,
                  hasIndependentLazyBooleanBody(property, in: classContext),
                  let propertySymbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            typeCheckBoundPropertyDecl(
                property,
                declID: declID,
                symbol: propertySymbol,
                ctx: classContext.with(currentDeclSymbol: propertySymbol),
                initialLocals: primaryConstructorLocals,
                solver: solver,
                diagnostics: diagnostics
            )
            driver.precheckedPropertyDecls.insert(declID)
        }
    }

    private func hasIndependentBooleanInitializer(_ property: PropertyDecl, ast: ASTModule) -> Bool {
        guard property.type == nil,
              property.initializer != nil,
              property.delegateExpression == nil,
              property.getter == nil,
              property.setter == nil,
              property.explicitBackingField == nil,
              property.receiverType == nil,
              let initializer = property.initializer,
              case .boolLiteral = ast.arena.expr(initializer)
        else {
            return false
        }
        return true
    }

    private func hasIndependentLazyBooleanBody(
        _ property: PropertyDecl,
        in ctx: TypeInferenceContext
    ) -> Bool {
        guard !property.isVar,
              property.type == nil,
              property.initializer == nil,
              property.getter == nil,
              property.setter == nil,
              property.explicitBackingField == nil,
              property.receiverType == nil,
              property.delegateBodyParams.isEmpty,
              let delegateExpression = property.delegateExpression,
              StdlibDelegateKind.detect(
                  delegateExpr: delegateExpression,
                  ast: ctx.ast,
                  interner: ctx.interner
              ) == .lazy,
              case let .expr(bodyExpr, _) = property.delegateBody
        else {
            return false
        }
        return isIndependentBooleanExpression(bodyExpr, in: ctx)
    }

    private func isIndependentBooleanExpression(
        _ exprID: ExprID,
        in ctx: TypeInferenceContext
    ) -> Bool {
        guard let expr = ctx.ast.arena.expr(exprID) else { return false }
        switch expr {
        case .boolLiteral:
            return true
        case let .unaryExpr(op, operand, _) where op == .not:
            return isIndependentBooleanExpression(operand, in: ctx)
        case let .binary(op, lhs, rhs, _):
            if op == .logicalAnd || op == .logicalOr {
                return isIndependentBooleanExpression(lhs, in: ctx)
                    && isIndependentBooleanExpression(rhs, in: ctx)
            }
            if op == .equal || op == .notEqual || op == .identityEqual || op == .notIdentityEqual {
                return isHeaderResolvedBooleanOperand(lhs, in: ctx)
                    && isHeaderResolvedBooleanOperand(rhs, in: ctx)
            }
            return false
        default:
            return false
        }
    }

    private func isHeaderResolvedBooleanOperand(
        _ exprID: ExprID,
        in ctx: TypeInferenceContext
    ) -> Bool {
        guard let expr = ctx.ast.arena.expr(exprID) else { return false }
        switch expr {
        case .boolLiteral, .nullLiteral:
            return true
        case let .nameRef(name, _):
            let propertySymbols = ctx.scope.lookup(name).filter { symbol in
                guard let kind = ctx.sema.symbols.symbol(symbol)?.kind else { return false }
                return kind == .property || kind == .field
            }
            guard !propertySymbols.isEmpty else { return false }
            return propertySymbols.allSatisfy { symbol in
                guard let type = ctx.sema.symbols.propertyType(for: symbol) else { return false }
                return type != ctx.sema.types.nullableAnyType
            }
        default:
            return false
        }
    }
}
