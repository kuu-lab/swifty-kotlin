extension DataFlowAnalyzer {
    func resolveStableReference(
        _ id: ExprID,
        locals: LocalBindings,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> (symbol: DataFlowReference, type: TypeID, isStable: Bool)? {
        guard let expr = ast.arena.expr(id) else { return nil }
        let local: LocalBindings.Value
        switch expr {
        case let .nameRef(name, _):
            if let resolved = locals[name] {
                local = resolved
            } else {
                // A bare member name and `this.member` must share a flow reference.
                // Only use the current receiver when lookup selects the same property;
                // a member on an outer receiver must not inherit this receiver's facts.
                guard sema.bindings.implicitReceiverMemberNames[id] != nil,
                      let property = sema.bindings.identifierSymbols[id],
                      isStableMemberProperty(property, ast: ast, sema: sema),
                      let receiver = locals[interner.intern("this")],
                      TypeCheckHelpers().lookupMemberProperty(
                          named: name, receiverType: receiver.type, sema: sema
                      )?.symbol == property,
                      let type = sema.bindings.exprType(for: id)
                else { return nil }
                return (DataFlowReference(root: receiver.symbol, properties: [property]), type, true)
            }
        case let .thisRef(label, _) where label == nil:
            guard let resolved = locals[interner.intern("this")] else { return nil }
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
        let mutatedInClosure = localDeclarations[local.symbol].map {
            localStability.isMutatedInClosure($0, sema: sema)
        } ?? false
        return (DataFlowReference(root: local.symbol), local.type, isStable && !mutatedInClosure)
    }

    private func isStableMemberProperty(_ property: SymbolID, ast: ASTModule, sema: SemaModule) -> Bool {
        if let cached = stableMemberProperties[property] { return cached }
        let stable = hasStableMemberDeclaration(property, ast: ast, sema: sema)
        stableMemberProperties[property] = stable
        return stable
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
