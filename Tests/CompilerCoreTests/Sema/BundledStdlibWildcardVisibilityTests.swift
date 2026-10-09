@testable import CompilerCore
import Testing
import TestStdlibCache

/// KUU-1032: invisible wildcard imports must not shadow public default imports.
@Suite
struct BundledStdlibWildcardVisibilityTests {
    @Test(arguments: [false, true], ["", "import kotlinx.io.*", "import kotlinx.io"])
    func minOfResolvesToPublicComparisons(
        allowDefaultStdlibLibrary: Bool, importDirective: String
    ) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        \(importDirective)
        val x = minOf(5L, 3L)
        fun probe(): Int = minOf(5, 3)
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            #expect((ctx.options.stdlibLibraryPath != nil) == allowDefaultStdlibLibrary)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let hidden = sema.symbols.lookupAll(fqName: ["kotlinx", "io", "minOf"].map(ctx.interner.intern))
            #expect(!hidden.isEmpty)
            #expect(hidden.allSatisfy { sema.symbols.symbol($0)?.visibility == .internal })

            var callTypes: [TypeID] = []
            for (exprID, binding) in sema.bindings.callBindings {
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .call(callee, _, _, _) = ast.arena.expr(exprID),
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      name == KnownCompilerNames(interner: ctx.interner).minOf
                else { continue }
                callTypes.append(try #require(sema.bindings.exprType(for: exprID)))
                let chosen = binding.chosenCallee
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "comparisons", "minOf"])
                #expect(symbol.visibility == .public)
                #expect(!hidden.contains(chosen))
            }
            #expect(callTypes.count == 2)
            #expect(callTypes.contains(sema.types.longType))
            #expect(callTypes.contains(sema.types.intType))
        }
    }

    @Test(arguments: [false, true])
    func explicitInternalImportStillReportsInvisibleAccess(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        import kotlinx.io.minOf as internalMin
        fun probe(): Long = internalMin(5L, 3L)
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0044" },
                    "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func sameModuleInternalWildcardImportRemainsAccessible() throws {
        try withTemporaryFiles(contents: [
            "package helper\ninternal fun minOf(a: Long, b: Long): Long = 42L",
            "import helper.*\nfun probe(): Long = minOf(5L, 3L)",
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .executable)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let helper = try #require(sema.symbols.lookup(fqName: ["helper", "minOf"].map(ctx.interner.intern)))
            #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == helper })
        }
    }
}
