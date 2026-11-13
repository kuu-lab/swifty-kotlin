/// The CST already uses the compilation's string IDs, so the block can be
/// parsed straight into the merged AST when Sema binds a call to it.
struct JVMInlineBodySyntax {
    let arena: SyntaxArena
    let block: NodeID
}

extension BuildASTPhase {
    func deferredJVMInlineBody(
        for function: FunDecl, from node: NodeID, in cst: SyntaxArena, interner: StringInterner
    ) -> JVMInlineBodySyntax? {
        guard function.isInline, function.annotations.isEmpty, function.contextReceivers.isEmpty,
              function.valueParams.allSatisfy({ $0.defaultValue == nil })
        else { return nil }

        let tokens = collectDirectTokens(from: node, in: cst)
        guard !tokens.contains(where: { $0.kind == .symbol(.assign) }),
              let block = cst.children(of: node).compactMap({ child -> NodeID? in
                  guard case let .node(id) = child, cst.node(id).kind == .block else { return nil }
                  return id
              }).first
        else { return nil }

        // Keep contracts and single-statement blocks available to the header
        // passes. Local nominals and super uses need the normal AST prepasses.
        let statements = collectBlockStatementGroups(from: block, in: cst)
        guard statements.count > 1,
              statements.allSatisfy({ group in
                  !group.raw.contains { token in
                      switch token.kind {
                      case .keyword(.class), .keyword(.interface), .keyword(.object),
                           .keyword(.typealias), .keyword(.super):
                          true
                      case let .identifier(name), let .backtickedIdentifier(name):
                          interner.resolve(name) == "contract"
                      default:
                          false
                      }
                  }
              })
        else { return nil }
        return JVMInlineBodySyntax(arena: cst, block: block)
    }
}

extension FunDecl {
    func replacingBody(_ body: FunctionBody) -> FunDecl {
        FunDecl(
            range: range, name: name, modifiers: modifiers, annotations: annotations,
            typeParams: typeParams, whereClauseRange: whereClauseRange, receiverType: receiverType,
            contextReceivers: contextReceivers, valueParams: valueParams, returnType: returnType,
            body: body, isSuspend: isSuspend, isInline: isInline, isTailrec: isTailrec,
            isScriptEntryPoint: isScriptEntryPoint, overrideKeywordRange: overrideKeywordRange,
            declarationKeywordRange: declarationKeywordRange
        )
    }
}
