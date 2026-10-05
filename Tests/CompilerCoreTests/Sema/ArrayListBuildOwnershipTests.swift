@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct ArrayListBuildOwnershipTests {
    @Test(arguments: [false, true])
    func buildIsPublishedInternalOnArrayListOwner(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        fun probe(list: ArrayList<Int>): List<Int> = list.build()
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let ownerFQName = ["kotlin", "collections", "ArrayList"].map(ctx.interner.intern)
            let owner = try #require(sema.symbols.lookup(fqName: ownerFQName))
            let members = sema.symbols.lookupAll(fqName: ownerFQName + [ctx.interner.intern("build")])
            #expect(members.count == 1)
            let build = try #require(members.first)
            let symbol = try #require(sema.symbols.symbol(build))
            #expect(sema.symbols.parentSymbol(for: build) == owner)
            #expect(symbol.visibility == .internal)
            #expect(sema.symbols.functionSignature(for: build)?.parameterTypes.isEmpty == true)
            #expect(sema.symbols.annotations(for: build).contains {
                KnownCompilerAnnotation.publishedApi.matches($0.annotationFQName)
            })

            if allowDefaultStdlibLibrary {
                #expect(ctx.options.stdlibLibraryPath != nil)
                #expect(symbol.flags.contains(.importedLibrary))
            } else {
                #expect(!symbol.flags.contains(.synthetic))
                let file = try #require(sema.symbols.sourceFileID(for: build))
                #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/collections/ArrayList/ArrayList.kt")
                #expect(sema.symbols.isSourceBackedSymbol(build))
                #expect(sema.symbols.externalLinkName(for: build) == nil)
            }

            let call = try #require(firstExprID(in: ast) { exprID, expr in
                guard case let .memberCall(_, name, _, _, _) = expr,
                      ctx.interner.resolve(name) == "build",
                      let range = ast.arena.exprRange(exprID)
                else { return false }
                return ctx.sourceManager.path(of: range.start.file) == path
            })
            #expect(sema.bindings.callBinding(for: call)?.chosenCallee == build)
        }
    }

    @Test(arguments: [false, true])
    func buildIsNotPublicClientAPI(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: "fun probe(list: ArrayList<Int>): List<Int> = list.build()") { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            #expect((ctx.options.stdlibLibraryPath != nil) == allowDefaultStdlibLibrary)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0044" })
        }
    }
}
