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

    @Test
    func testURLReadBytesFunctionTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import java.net.URL
            import kotlin.io.readBytes

            fun read(url: URL): ByteArray = url.readBytes()
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testURLReadBytesFunctionIsRegistered ===
            do {

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

            // === testURLReadBytesFunctionResolvesInSource ===
            do {
                let path0 = paths[0]
                let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
                #expect(!path0Diagnostics.contains(where: { $0.severity == .error }), "Expected testURLReadBytesFunctionResolvesInSource to resolve cleanly, got: \(path0Diagnostics)")
            }
        }
    }

}
