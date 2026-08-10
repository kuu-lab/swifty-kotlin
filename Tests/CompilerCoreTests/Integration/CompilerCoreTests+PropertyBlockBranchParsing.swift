#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// BUG-047: a top-level (or class member) property initializer ending in an
// expression with several top-level `{ }` blocks (`if/else`, `else if` chains)
// used to lose everything after the first block, because `parseTail` split off
// a single `.block` CST node and stopped -- only `try`/`catch`/`finally`
// continuations were handled. The `else` branch never reached the property's
// CST, so `val v = if (c) { "yes" } else { "no" }` silently evaluated to
// undefined behaviour on the false path.
extension CompilerCoreTests {
    private func memberProperty(
        named name: String,
        ofClass className: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> PropertyDecl? {
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .classDecl(classDecl) = decl,
                      interner.resolve(classDecl.name) == className
                else { continue }
                for propertyDeclID in classDecl.memberProperties {
                    guard let propertyDecl = ast.arena.decl(propertyDeclID),
                          case let .propertyDecl(property) = propertyDecl,
                          interner.resolve(property.name) == name
                    else { continue }
                    return property
                }
            }
        }
        return nil
    }

    @Test func testPropertyBlockBranchParsing() throws {
        let sources: [String] = [
            """
            package sample0
            val topLevelIf = if (1 > 2) { "yes" } else { "no" }
            """,

            """
            package sample1
            val chained = if (1 > 2) { 1 } else if (2 > 3) { 2 } else { 3 }
            """,

            """
            package sample2
            class Holder {
                val member = if (1 > 2) { "yes" } else { "no" }
            }
            """,

            """
            package sample3
            val guarded = try { 1 } catch (e: Exception) { 2 } finally { }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            let interner = ctx.interner

            do {
                let property = try #require(topLevelProperty(named: "topLevelIf", in: ast, interner: interner))
                let initializerID = try #require(property.initializer)
                guard let initializerExpr = ast.arena.expr(initializerID),
                      case let .ifExpr(_, _, elseExpr, _) = initializerExpr
                else {
                    Issue.record("Expected property initializer to parse as an if expression.")
                    return
                }
                #expect(elseExpr != nil)
            }

            do {
                let property = try #require(topLevelProperty(named: "chained", in: ast, interner: interner))
                let initializerID = try #require(property.initializer)
                guard let initializerExpr = ast.arena.expr(initializerID),
                      case let .ifExpr(_, _, outerElseID, _) = initializerExpr,
                      let nestedID = outerElseID,
                      let nestedExpr = ast.arena.expr(nestedID),
                      case let .ifExpr(_, _, nestedElseID, _) = nestedExpr
                else {
                    Issue.record("Expected property initializer to parse as a nested if/else-if expression.")
                    return
                }
                #expect(nestedElseID != nil)
            }

            do {
                let property = try #require(
                    memberProperty(named: "member", ofClass: "Holder", in: ast, interner: interner)
                )
                let initializerID = try #require(property.initializer)
                guard let initializerExpr = ast.arena.expr(initializerID),
                      case let .ifExpr(_, _, elseExpr, _) = initializerExpr
                else {
                    Issue.record("Expected member property initializer to parse as an if expression.")
                    return
                }
                #expect(elseExpr != nil)
            }

            do {
                let property = try #require(topLevelProperty(named: "guarded", in: ast, interner: interner))
                let initializerID = try #require(property.initializer)
                guard let initializerExpr = ast.arena.expr(initializerID),
                      case let .tryExpr(_, catchClauses, finallyExpr, _) = initializerExpr
                else {
                    Issue.record("Expected property initializer to parse as a try expression.")
                    return
                }
                #expect(catchClauses.count == 1)
                #expect(finallyExpr != nil)
            }
        }
    }
}
#endif
