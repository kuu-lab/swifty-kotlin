#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

/// Coroutine state machine dispatch labels start at this offset.
let coroutineDispatchLabelBase: Int32 = 1000

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
#endif
