#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

func findAllKIRFunctions(in module: KIRModule) -> [KIRFunction] {
    CompilerTestSupport.findAllKIRFunctions(in: module)
}

func findKIRFunction(
    named name: String,
    in module: KIRModule,
    interner: StringInterner,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> KIRFunction {
    try CompilerTestSupport.findKIRFunction(named: name, in: module, interner: interner, file: file, line: line)
}

func findKIRFunctionBody(
    named name: String,
    in module: KIRModule,
    interner: StringInterner,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> [KIRInstruction] {
    try CompilerTestSupport.findKIRFunctionBody(named: name, in: module, interner: interner, file: file, line: line)
}

func extractCallees(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [String] {
    CompilerTestSupport.extractCallees(from: body, interner: interner)
}

func extractVirtualCallees(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [String] {
    body.compactMap { instruction -> String? in
        guard case let .virtualCall(_, callee, _, _, _, _, _, _) = instruction else { return nil }
        return interner.resolve(callee)
    }
}

func extractThrowFlags(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [String: [Bool]] {
    CompilerTestSupport.extractThrowFlags(from: body, interner: interner)
}

private func exprID(
    in ast: ASTModule,
    scanning indices: some Sequence<Int>,
    where predicate: (ExprID, Expr) -> Bool
) -> ExprID? {
    for index in indices {
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID) else { continue }
        if predicate(exprID, expr) { return exprID }
    }
    return nil
}

func firstExprID(
    in ast: ASTModule,
    where predicate: (ExprID, Expr) -> Bool
) -> ExprID? {
    exprID(in: ast, scanning: ast.arena.exprs.indices, where: predicate)
}

func lastExprID(
    in ast: ASTModule,
    where predicate: (ExprID, Expr) -> Bool
) -> ExprID? {
    exprID(in: ast, scanning: ast.arena.exprs.indices.reversed(), where: predicate)
}

/// First call expression whose callee is a bare name reference to `name`.
func nameRefCallExprID(
    named name: String,
    in ast: ASTModule,
    interner: StringInterner
) -> ExprID? {
    firstExprID(in: ast) { _, expr in
        guard case let .call(calleeExprID, _, _, _) = expr,
              let calleeExpr = ast.arena.expr(calleeExprID),
              case let .nameRef(calleeName, _) = calleeExpr
        else {
            return false
        }
        return interner.resolve(calleeName) == name
    }
}

extension KIRDecl {
    /// The wrapped function, or `nil` when this declaration is not a function.
    var function: KIRFunction? {
        guard case let .function(fn) = self else { return nil }
        return fn
    }
}

/// Build a single-function `KIRModule` around `body` — the fixture shape every
/// pass-level lowering test needs.
func makeModule(
    body: [KIRInstruction],
    interner: StringInterner,
    arena: KIRArena,
    fnName: String = "main",
    returnType: TypeID = TypeSystem().unitType
) -> (KIRModule, KIRDeclID) {
    let fn = KIRFunction(
        symbol: SymbolID(rawValue: 1),
        name: interner.intern(fnName),
        params: [],
        returnType: returnType,
        body: body,
        isSuspend: false,
        isInline: false
    )
    let declID = arena.appendDecl(.function(fn))
    let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
    return (module, declID)
}

func bodyInDecl(_ declID: KIRDeclID, module: KIRModule) -> [KIRInstruction] {
    module.arena.decl(declID)?.function?.body ?? []
}

func calleesInDecl(_ declID: KIRDeclID, module: KIRModule, interner: StringInterner) -> [String] {
    extractCallees(from: bodyInDecl(declID, module: module), interner: interner)
}

#endif
