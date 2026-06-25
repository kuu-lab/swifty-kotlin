@testable import CompilerCore
import XCTest

func makeSema(
    source: String = "fun noop() {}"
) throws -> (SemaModule, StringInterner) {
    var result: (SemaModule, StringInterner)?
    try withTemporaryFile(contents: source) { path in
        let ctx = makeCompilationContext(inputs: [path])
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        result = (sema, ctx.interner)
    }
    return try XCTUnwrap(result)
}

func allExternalLinks(
    fqPath: [String],
    sema: SemaModule,
    interner: StringInterner
) -> Set<String> {
    let interned = fqPath.map { interner.intern($0) }
    return Set(
        sema.symbols.lookupAll(fqName: interned)
            .compactMap { sema.symbols.externalLinkName(for: $0) }
    )
}

func memberCallExprIDs(
    named name: String,
    in ast: ASTModule,
    interner: StringInterner
) -> [ExprID] {
    ast.arena.exprs.indices.compactMap { index in
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID),
              case let .memberCall(_, callee, _, _, _) = expr,
              interner.resolve(callee) == name
        else {
            return nil
        }
        return exprID
    }
}
