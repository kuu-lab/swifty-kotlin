#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-PATH-FN-036: `fun URI.toPath(): Path` in kotlin.io.path.
///
/// Verifies that the synthetic `kotlin.io.path.toPath` extension on
/// `java.net.URI` resolves cleanly and that its external link name targets
/// the runtime export `kk_uri_toPath`.
@Suite
struct PathToPathFunctionTests {
    @Test func testUriToPathExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.net.URI
        import kotlin.io.path.Path
        import kotlin.io.path.toPath

        fun convert(uri: URI): Path {
            return uri.toPath()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "URI.toPath() extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let uriSymbol = try #require(symbols.lookup(fqName: ["java", "net", "URI"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let uriType = types.make(.classType(ClassType(classSymbol: uriSymbol, args: [], nullability: .nonNull)))

            let toPathSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "toPath"].map(interner.intern))
            let toPath = try #require(toPathSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == uriType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: toPath) == "kk_uri_toPath")

            let signature = try #require(symbols.functionSignature(for: toPath))
            #expect(signature.receiverType == uriType)
            #expect(signature.returnType == pathType)
            #expect(signature.parameterTypes == [])
            #expect(signature.valueParameterHasDefaultValues == [])
            #expect(signature.valueParameterIsVararg == [])
            #expect(signature.valueParameterSymbols.count == 0)
        }
    }

    @Test func testUriToPathFunctionLinkNameIsRegistered() throws {
        let source = """
        import java.net.URI
        import kotlin.io.path.toPath

        fun pathOf(uri: URI) = uri.toPath()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected kotlin.io.path.toPath to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "io", "path", "toPath"].map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: fq)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                links.contains("kk_uri_toPath"),
                "kotlin.io.path.toPath must link to kk_uri_toPath; got: \(links)"
            )
        }
    }
}
#endif
