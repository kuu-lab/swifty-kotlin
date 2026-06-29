@testable import CompilerCore
import Foundation
import Testing

/// Verifies the STDLIB-IO-FN-030 synthetic stub for `URL.readBytes(): ByteArray`.
///
/// The extension is registered as a package-level function in `kotlin.io`:
///   `fun URL.readBytes(): ByteArray`
/// and is backed by the runtime entry point `kk_url_readBytes`.
@Suite
struct URLReadBytesFunctionTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "URL.readBytes surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testURLReadBytesFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let urlSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("net"),
            interner.intern("URL"),
        ]))
        let urlType = sema.types.make(.classType(ClassType(
            classSymbol: urlSymbol,
            args: [],
            nullability: .nonNull
        )))
        let byteArraySymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("ByteArray"),
        ]))
        let byteArrayType = sema.types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("readBytes"),
        ]

        let functionSymbol = try #require(sema.symbols.lookupAll(fqName: functionFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == urlType
                && signature.parameterTypes.isEmpty
                && signature.returnType == byteArrayType
        })
        #expect(sema.symbols.externalLinkName(for: functionSymbol) == "kk_url_readBytes")
    }

    @Test
    func testURLReadBytesFunctionResolvesInSource() throws {
        let source = """
        import java.net.URL
        import kotlin.io.readBytes

        fun read(url: URL): ByteArray = url.readBytes()
        """

        _ = try makeSema(source: source)
    }
}
