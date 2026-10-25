#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct FullyQualifiedTypeAliasConstructorTests {
    @Test func resolvesConstructorCallsThroughUnqualifiedJavaLangAliases() throws {
        let facade = """
        package java.lang
        public typealias Object = kotlin.Any
        """
        let consumer = """
        fun makeAny() = Any()
        fun makeObject() = Object()
        """
        try withTemporaryFiles(contents: [facade, consumer]) { inputs in
            let ctx = makeCompilationContext(
                inputs: inputs,
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            _ = ctx.sourceManager.addFile(
                path: inputs[0],
                contents: Data(facade.utf8),
                origin: .bundledStdlib
            )
            _ = ctx.sourceManager.addFile(path: inputs[1], contents: Data(consumer.utf8))
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")

            let ast = try #require(ctx.ast)
            let anyCall = try #require(firstExprID(in: ast, path: inputs[1], ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else {
                    return false
                }
                return ctx.interner.resolve(name) == "Any"
            })
            let objectCall = try #require(firstExprID(in: ast, path: inputs[1], ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else {
                    return false
                }
                return ctx.interner.resolve(name) == "Object"
            })
            let sema = try #require(ctx.sema)
            let anyBinding = try #require(sema.bindings.callBinding(for: anyCall))
            let objectBinding = try #require(sema.bindings.callBinding(for: objectCall))
            #expect(sema.symbols.symbol(objectBinding.chosenCallee)?.kind == .constructor)
            #expect(objectBinding.chosenCallee == anyBinding.chosenCallee)
            let owner = try #require(sema.symbols.parentSymbol(for: objectBinding.chosenCallee))
            #expect(sema.symbols.symbol(owner)?.fqName.map(ctx.interner.resolve) == ["kotlin", "Any"])
        }
    }

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
