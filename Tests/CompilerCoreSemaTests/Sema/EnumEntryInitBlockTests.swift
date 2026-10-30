#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct EnumEntryInitBlockTests {
    @Test
    func initBlockInitializesEntryPropertiesInDeclarationOrder() throws {
        let source = """
        enum class E {
            A {
                val before = 40
                val value: Int
                init { value = before + 2 }
                val after = value
            }
        }
        """
        let ctx = try semaContext(source)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let enumDeclID = try #require(ast.files.first?.topLevelDecls.first)
        let enumDecl = try #require(ast.arena.decl(enumDeclID))
        guard case let .classDecl(decl) = enumDecl else {
            Issue.record("Expected an enum class declaration")
            return
        }
        let entry = try #require(decl.enumEntries.first)
        #expect(entry.initBlocks.count == 1)
        #expect(entry.classBodyInitOrder == [
            .property(0), .property(1), .initBlock(0), .property(2)
        ])
    }

    @Test
    func incompleteEntryInitializationPathsAreRejected() throws {
        let ctx = try semaContext("""
        enum class E {
            A {
                val value: Int
                init { if (true) value = 1 }
            }
        }
        """)

        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0424" })
    }

    @Test
    func entryPropertyWithoutInitializerOrInitBlockIsRejected() throws {
        let ctx = try semaContext("enum class E { A { val value: Int } }")

        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0424" })
    }

    private func semaContext(_ source: String) throws -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        let ctx = makeCompilationContext(
            inputs: [path], includeStdlib: false, allowDefaultStdlibLibrary: false
        )
        try runSema(ctx)
        return ctx
    }
}
#endif
