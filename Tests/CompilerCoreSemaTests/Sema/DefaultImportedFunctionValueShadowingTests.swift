#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// KUU-2412: a same-package value must not hide a default-imported function call.
@Suite
struct DefaultImportedFunctionValueShadowingTests {
    @Test(arguments: [false, true])
    func packagePropertyDoesNotShadowDefaultImportedFunction(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSource("""
        package kuu2322emptymap

        val emptyMap: Map<String, String> = emptyMap()
        """, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        let errorSummaries = errors.map { diagnostic in
            let path = diagnostic.primaryRange.map { ctx.sourceManager.path(of: $0.start.file) } ?? "<unknown>"
            return "\(diagnostic.code): \(diagnostic.message) at \(path)"
        }
        #expect(errors.isEmpty, Comment(rawValue: errorSummaries.joined(separator: "\n")))

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var callCount = 0
        for index in ast.arena.exprs.indices {
            let call = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(call),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  case let .call(callee, _, _, _) = ast.arena.expr(call),
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  ctx.interner.resolve(name) == "emptyMap"
            else {
                continue
            }

            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            let symbol = try #require(sema.symbols.symbol(chosen))
            #expect(symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "emptyMap"])
            callCount += 1
        }
        #expect(callCount == 1)
    }
}
#endif
