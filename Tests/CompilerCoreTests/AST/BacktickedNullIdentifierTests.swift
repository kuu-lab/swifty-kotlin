#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct BacktickedNullIdentifierTests {
    @Test
    func literalAndEscapedIdentifierRemainDistinct() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun main() {
            val `null` = 14
            println(`null`)
            println(`null` + 1)
            println(null)
        }
        """, includeStdlib: false)
        let nullName = KnownCompilerNames(interner: ctx.interner).null
        let references = ast.arena.exprs.filter {
            guard case let .nameRef(name, _) = $0 else { return false }
            return name == nullName
        }
        let literals = ast.arena.exprs.filter {
            if case .nullLiteral = $0 { return true }
            return false
        }
        #expect(references.count == 2)
        #expect(literals.count == 1)
    }

    @Test
    func escapedIdentifierBindsToVariable() throws {
        let (_, ctx) = try buildASTModule(from: """
        fun read(`null`: Int): Int = `null` + 1
        fun literal(): Int? = null
        """, includeStdlib: false)
        try SemaPhase().run(ctx)
        #expect(!ctx.diagnostics.hasError)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let nullName = KnownCompilerNames(interner: ctx.interner).null
        var referenceCount = 0
        for (index, expr) in ast.arena.exprs.enumerated() {
            guard case let .nameRef(name, _) = expr,
                  name == nullName else { continue }
            referenceCount += 1
            let id = ExprID(rawValue: Int32(index))
            #expect(sema.bindings.identifierSymbols[id] != nil)
            #expect(sema.bindings.exprType(for: id) == sema.types.intType)
        }
        #expect(referenceCount == 1)
    }

    @Test
    func whenVariableAndLiteralHaveDistinctConditionKeys() throws {
        let (_, ctx) = try buildASTModule(from: """
        fun choose(value: Int?, `null`: Int): Int = when (value) {
            `null` -> 1
            null -> 2
            else -> 3
        }
        """, includeStdlib: false)
        try SemaPhase().run(ctx)
        #expect(!ctx.diagnostics.hasError)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let conditions = try #require(ast.arena.exprs.compactMap { expr -> [ExprID]? in
            guard case let .whenExpr(_, branches, _, _) = expr else { return nil }
            return branches.flatMap(\.conditions)
        }.first)
        #expect(conditions.count == 2)
        let keys = conditions.map {
            whenConditionKey(for: $0, ast: ast, sema: sema, interner: ctx.interner)
        }
        #expect(keys[0] != keys[1])
        #expect(keys[1] == "null")
    }

    @Test
    func undeclaredEscapedNullIsUnresolved() throws {
        let (_, ctx) = try buildASTModule(from: "fun read(): Int? = `null`", includeStdlib: false)
        try SemaPhase().run(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0022" })
    }
}
#endif
