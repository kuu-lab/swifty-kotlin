@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

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

    /// KUU-4232: an `internal` declaration in the bundled stdlib module must
    /// not win the same-package classifier tier over a visible
    /// wildcard-imported declaration. The bundled stdlib keeps internal
    /// classifiers such as `kotlinx.coroutines.flow.ChannelFlowImpl`;
    /// upstream-style sources declare their own same-named classifier in a
    /// subpackage and import it with a wildcard, as `ChannelAsFlow` does in
    /// kotlinx-coroutines Channels.kt.
    @Test
    func samePackageInternalStdlibDeclDoesNotShadowWildcardImport() throws {
        try withTemporaryFiles(contents: [
            """
            package kotlinx.coroutines.flow.internal
            internal open class ChannelFlowImpl<T>
            """,
            """
            package kotlinx.coroutines.flow
            import kotlinx.coroutines.flow.internal.*
            class ChannelAsFlow<T> : ChannelFlowImpl<T>()
            fun take(flow: ChannelFlowImpl<*>): String = "ok"
            """,
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .executable)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let owner = try #require(sema.symbols.lookup(
                fqName: ["kotlinx", "coroutines", "flow", "ChannelAsFlow"].map(ctx.interner.intern)
            ))
            let supertypes = sema.symbols.directSupertypes(for: owner)
            #expect(supertypes.count == 1)
            let superSymbol = try #require(supertypes.first.flatMap { sema.symbols.symbol($0) })
            #expect(superSymbol.fqName.map(ctx.interner.resolve)
                == ["kotlinx", "coroutines", "flow", "internal", "ChannelFlowImpl"])
        }
    }

    /// KUU-4232: skipping invisible internal candidates must not swallow the
    /// visibility diagnostic when no visible alternative exists — kotlinc
    /// still resolves the inaccessible classifier and reports the access
    /// error.
    @Test
    func internalStdlibDeclWithoutAlternativeStillReportsInvisibleAccess() throws {
        try withTemporaryFile(contents: """
        package kotlinx.coroutines.flow
        class ChannelAsFlow<T> : ChannelFlowImpl<T>()
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .executable)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0044" },
                    "\(ctx.diagnostics.diagnostics)")
        }
    }
}
