/// `lateinit` storage must hold `runtimeNullSentinelInt` until it is first
/// assigned: `kk_lateinit_get_or_throw` / `kk_lateinit_is_initialized`
/// compare against that sentinel, while a freshly allocated object (or a
/// zero-initialized module global backing a singleton) holds `0`, which the
/// read path would treat as a live value.
///
/// kotlinc emits no store for a `lateinit` without an initializer — the JVM
/// default `null` is already the sentinel. Here the seed must therefore run
/// *before* the superclass constructor, so a virtual call made from a
/// superclass `init` block that assigns the property is not wiped by a store
/// at the property's position in `classBodyInitOrder`.
extension KIRLoweringDriver {
    func lateinitSentinelPropertySymbols(
        _ memberProperties: [DeclID],
        shared: KIRLoweringSharedContext
    ) -> [SymbolID] {
        memberProperties.compactMap { propDeclID in
            guard let decl = shared.ast.arena.decl(propDeclID),
                  case let .propertyDecl(prop) = decl,
                  prop.modifiers.contains(.lateinit),
                  prop.initializer == nil,
                  prop.delegateExpression == nil,
                  prop.explicitBackingField == nil
            else {
                return nil
            }
            return shared.sema.bindings.declSymbols[propDeclID]
        }
    }

    func nullInitializerPropertySymbols(
        _ memberProperties: [DeclID],
        shared: KIRLoweringSharedContext
    ) -> [SymbolID] {
        memberProperties.compactMap { propDeclID in
            guard let decl = shared.ast.arena.decl(propDeclID),
                  case let .propertyDecl(prop) = decl,
                  let initializer = prop.initializer,
                  case .nullLiteral = shared.ast.arena.expr(initializer),
                  prop.delegateExpression == nil,
                  prop.explicitBackingField == nil
            else {
                return nil
            }
            return shared.sema.bindings.declSymbols[propDeclID]
        }
    }

    func emitSingletonLateinitSentinels(
        _ memberProperties: [DeclID],
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        for propSymbol in lateinitSentinelPropertySymbols(memberProperties, shared: shared) {
            let targetSymbol = sema.symbols.backingFieldSymbol(for: propSymbol) ?? propSymbol
            let propType = sema.symbols.propertyType(for: targetSymbol) ?? sema.types.anyType
            let nullExpr = arena.appendExpr(.null, type: propType)
            body.append(.constValue(result: nullExpr, value: .null))
            let targetRef = arena.appendExpr(.symbolRef(targetSymbol), type: propType)
            body.append(.constValue(result: targetRef, value: .symbolRef(targetSymbol)))
            body.append(.copy(from: nullExpr, to: targetRef))
        }
    }
}
