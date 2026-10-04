#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// An `init {}` member in an object expression used to make
/// `parseObjectLiteralDecl` reject the whole body (`nil` decl), so the literal
/// lost every member and `g.greet()` panicked with "Virtual dispatch failed".
/// The init blocks must be collected, in declaration order relative to the
/// property initializers.
///
/// See `Scripts/diff_cases/object_literal_init_block.kt`.
@Suite
struct ObjectLiteralInitBlockTests {
    private func objectLiteralDecls(_ source: String) throws -> [ObjectDecl] {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        try runFrontend(ctx)
        let ast = try #require(ctx.ast)
        return ast.arena.exprs.compactMap { expr -> ObjectDecl? in
            guard case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  case let .objectDecl(objectDecl)? = ast.arena.decl(declID)
            else { return nil }
            return objectDecl
        }
    }

    @Test func initBlocksAreCollectedInDeclarationOrder() throws {
        let decls = try objectLiteralDecls("""
        interface G { fun greet(): String }
        fun main() {
            val g = object : G {
                val a = 1
                init { println("init 1") }
                val b = 2
                init { println("init 2") }
                override fun greet() = "hi"
            }
            val one = object { init { println("x") }; val v = 1 }
        }
        """)
        #expect(decls.count == 2)
        let g = try #require(decls.first { $0.memberFunctions.count == 1 })
        #expect(g.memberProperties.count == 2)
        #expect(g.initBlocks.count == 2)
        #expect(g.classBodyInitOrder == [.property(0), .initBlock(0), .property(1), .initBlock(1)])

        let one = try #require(decls.first { $0.memberFunctions.isEmpty })
        #expect(one.initBlocks.count == 1)
        #expect(one.classBodyInitOrder == [.initBlock(0), .property(0)])
    }
}
#endif
