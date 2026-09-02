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

func firstExprID(
    in ast: ASTModule,
    where predicate: (ExprID, Expr) -> Bool
) -> ExprID? {
    for index in ast.arena.exprs.indices {
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID) else { continue }
        if predicate(exprID, expr) { return exprID }
    }
    return nil
}

func lastExprID(
    in ast: ASTModule,
    where predicate: (ExprID, Expr) -> Bool
) -> ExprID? {
    for index in ast.arena.exprs.indices.reversed() {
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID) else { continue }
        if predicate(exprID, expr) { return exprID }
    }
    return nil
}
#endif
