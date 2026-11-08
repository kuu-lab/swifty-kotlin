extension DataFlowAnalyzer {
    func resolveStableReference(
        _ id: ExprID,
        locals: LocalBindings,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        narrowingType: TypeID? = nil,
        narrowingToNonNull: Bool = false
    ) -> (symbol: DataFlowReference, type: TypeID, isStable: Bool)? {
        guard let expr = ast.arena.expr(id) else { return nil }
        let local: LocalBindings.Value
        switch expr {
        case let .nameRef(name, _):
            if let resolved = locals[name] {
                local = resolved
            } else if let property = sema.bindings.identifierSymbols[id],
                      isStableTopLevelProperty(property, ast: ast, sema: sema),
                      let type = sema.bindings.exprType(for: id)
            {
                return (DataFlowReference(root: property), type, true)
            } else {
                // A bare member name and `this.member` must share a flow reference.
                // Only use the current receiver when lookup selects the same property;
                // a member on an outer receiver must not inherit this receiver's facts.
                guard sema.bindings.implicitReceiverMemberNames[id] != nil,
                      let property = sema.bindings.identifierSymbols[id],
                      isStableMemberProperty(property, ast: ast, sema: sema),
                      let type = sema.bindings.exprType(for: id)
                else { return nil }
                // A member resolved through an *outer* implicit receiver keeps
                // its own flow reference — `alias` inside `buildString {}`
                // belongs to the enclosing class's `this`, not the lambda's
                // StringBuilder receiver, so `if (alias != null)` can narrow it
                // inside the inline lambda (KUU-4473).
                if let outerSymbol = sema.bindings.implicitReceiverOuterReceiver(for: id),
                   isStableReceiverValueSymbol(outerSymbol, sema: sema)
                {
                    return (DataFlowReference(root: outerSymbol, properties: [property]), type, true)
                }
                guard let receiver = locals[interner.intern("this")],
                      TypeCheckHelpers().lookupMemberProperty(
                          named: name, receiverType: receiver.type, sema: sema
                      )?.symbol == property
                else { return nil }
                return (DataFlowReference(root: receiver.symbol, properties: [property]), type, true)
            }
        case let .thisRef(label, _):
            guard let resolved = locals[interner.intern("this")] else { return nil }
            if label != nil, sema.bindings.identifierSymbols[id] != resolved.symbol {
                // A labeled `this@…` shares the unqualified receiver's flow
                // slot only when it denotes that same receiver — e.g.
                // `this@func` inside the extension function `func`, which
                // binds the same synthetic receiver parameter symbol. When the
                // label instead binds a different *receiver value* (an
                // extension receiver parameter or a labeled lambda's
                // receiver), root the reference at that symbol so
                // `this@func.alias` smart-casts inside inner lambdas.
                // `this@Class` binds the classifier itself, which would
                // conflate different instances, so it keeps the nil result.
                guard let bound = sema.bindings.identifierSymbols[id],
                      isStableReceiverValueSymbol(bound, sema: sema),
                      let type = sema.bindings.exprType(for: id)
                else { return nil }
                return (DataFlowReference(root: bound), type, true)
            }
            local = resolved
        case let .memberCall(receiver, _, _, args, _):
            guard args.isEmpty, !ast.arena.isExplicitCall(id),
                  let property = sema.bindings.identifierSymbols[id],
                  isStableMemberProperty(property, ast: ast, sema: sema),
                  let base = resolveStableReference(receiver, locals: locals, ast: ast, sema: sema, interner: interner),
                  base.isStable,
                  !locals.values.contains(where: {
                      $0.symbol == base.symbol.root && $0.isMutable
                          && !stableMutableReceivers.contains($0.symbol)
                  }),
                  let type = sema.bindings.exprType(for: id)
            else { return nil }
            var reference = base.symbol
            reference.properties.append(property)
            return (reference, type, true)
        default:
            return nil
        }
        let isStable: Bool = if let symbol = sema.symbols.symbol(local.symbol) {
            symbol.kind == .valueParameter || symbol.kind == .local
        } else {
            true
        }
        let targetType = narrowingType ?? (narrowingToNonNull ? sema.types.makeNonNullable(local.type) : nil)
        let mutatedInClosure = localDeclarations[local.symbol].map { declaration in
            guard localStability.isMutatedInClosure(declaration, sema: sema) else { return false }
            guard let targetType else { return true }
            // localDeclarations tracks mutable locals only; immutable aliases
            // must also be excluded from this conservative value proof.
            let localSymbols = Set(sema.symbols.allSymbols().filter { $0.kind == .local }.map(\.id))
            return !localStability.closureWritesPreserve(
                declaration, type: targetType, ast: ast, sema: sema, localSymbols: localSymbols
            )
        } ?? false
        return (DataFlowReference(root: local.symbol), local.type, isStable && !mutatedInClosure)
    }

    /// Flow-fact roots must denote stable *values*: synthetic receiver
    /// parameters and lambda receivers are per-instance `this` values, and
    /// singleton `object`/local/parameter symbols are stable bindings. A
    /// classifier symbol (class/interface) would conflate different
    /// instances, so it is not a valid root.
    private func isStableReceiverValueSymbol(_ symbol: SymbolID, sema: SemaModule) -> Bool {
        if symbol.rawValue < 0 { return true }
        switch sema.symbols.symbol(symbol)?.kind {
        case .object, .local, .valueParameter:
            return true
        default:
            return false
        }
    }

    func isStableMemberProperty(_ property: SymbolID, ast: ASTModule, sema: SemaModule) -> Bool {
        if let cached = stableMemberProperties[property] { return cached }
        let stable = hasStableMemberDeclaration(property, ast: ast, sema: sema)
        stableMemberProperties[property] = stable
        return stable
    }

    func isStableTopLevelProperty(_ property: SymbolID, ast: ASTModule, sema: SemaModule) -> Bool {
        guard sema.symbols.symbol(property)?.kind == .property,
              sema.symbols.extensionPropertyReceiverType(for: property) == nil,
              sema.symbols.parentSymbol(for: property).map({
                  sema.symbols.symbol($0)?.kind == .package
              }) ?? true
        else {
            return false
        }
        return isStableMemberProperty(property, ast: ast, sema: sema)
    }

    private func hasStableMemberDeclaration(_ property: SymbolID, ast: ASTModule, sema: SemaModule) -> Bool {
        guard let symbol = sema.symbols.symbol(property), symbol.kind == .property,
              !symbol.flags.contains(.mutable), !symbol.flags.contains(.openType),
              !symbol.flags.contains(.abstractType), !symbol.flags.contains(.importedLibrary),
              sema.symbols.extensionPropertyReceiverType(for: property) == nil,
              let declID = sema.bindings.declSymbols.first(where: { $0.value == property })?.key,
              case let .propertyDecl(decl) = ast.arena.decl(declID)
        else { return false }
        if decl.modifiers.contains(.override), !decl.modifiers.contains(.final),
           let owner = sema.symbols.parentSymbol(for: property),
           let ownerSymbol = sema.symbols.symbol(owner),
           ownerSymbol.flags.contains(.openType) || ownerSymbol.flags.contains(.abstractType)
        {
            return false
        }
        return decl.delegateExpression == nil
            && !decl.modifiers.contains(.open) && !decl.modifiers.contains(.abstract)
            && (decl.getter == nil || decl.getter?.body == .unit)
    }

    func whenElseState(subjectSymbol: SymbolID, subjectType: TypeID, hasExplicitNullBranch: Bool, base: DataFlowState, sema: SemaModule) -> DataFlowState {
        whenElseState(subjectSymbol: DataFlowReference(root: subjectSymbol), subjectType: subjectType, hasExplicitNullBranch: hasExplicitNullBranch, base: base, sema: sema)
    }

    func whenNonNullBranchState(subjectSymbol: SymbolID, subjectType: TypeID, base: DataFlowState, sema: SemaModule) -> DataFlowState {
        whenNonNullBranchState(subjectSymbol: DataFlowReference(root: subjectSymbol), subjectType: subjectType, base: base, sema: sema)
    }
}
