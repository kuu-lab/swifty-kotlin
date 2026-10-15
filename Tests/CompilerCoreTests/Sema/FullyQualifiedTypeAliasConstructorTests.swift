#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct FullyQualifiedTypeAliasConstructorTests {
    @Test func resolvesConstructorCallsThroughQualifiedLibraryTypeAliases() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path])
        _ = ctx.sourceManager.addFile(path: path, contents: Data("""
        fun makeFailure() = java.io.IOException("failure")
        """.utf8))
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let call = try #require(memberCallExprIDs(
            named: "IOException", in: ast, path: path, ctx: ctx, interner: ctx.interner
        ).first)
        let sema = try #require(ctx.sema)
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor)
        let owner = try #require(sema.symbols.parentSymbol(for: binding.chosenCallee))
        #expect(sema.symbols.symbol(owner)?.fqName.map(ctx.interner.resolve) == ["kotlinx", "io", "IOException"])
    }
}
#endif
