#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-PROP-003: File.invariantSeparatorsPath
//
// Sema-surface tests for the `kotlin.io.invariantSeparatorsPath` extension
// property on `java.io.File`.
//
// Kotlin signature:
//   public val File.invariantSeparatorsPath: String
//     get() = if (File.separatorChar != '/') path.replace(File.separatorChar, '/') else path

@Suite
struct FileInvariantSeparatorsPathTests {
    @Test func testFileInvariantSeparatorsPathResolvesInSource() throws {
        let source = """
        import java.io.File
        import kotlin.io.invariantSeparatorsPath

        fun normalized(file: File): String {
            return file.invariantSeparatorsPath
        }

        fun length(file: File): Int {
            val normalized: String = file.invariantSeparatorsPath
            return normalized.length
        }

        fun main() {
            val s: String = File("/tmp/foo").invariantSeparatorsPath
            println(s)
        }

        fun stub(file: File): String = file.invariantSeparatorsPath
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "File.invariantSeparatorsPath should resolve as String: \(ctx.diagnostics.diagnostics.map { $0.message })"
            )

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let fileSymbol = try #require(
                symbols.lookup(fqName: ["java", "io", "File"].map(interner.intern))
            )
            let fileType = types.make(.classType(ClassType(
                classSymbol: fileSymbol, args: [], nullability: .nonNull
            )))

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "invariantSeparatorsPath"].map(interner.intern)
            )
            let property = try #require(candidates.first { symbolID in
                guard symbols.symbol(symbolID)?.kind == .property else {
                    return false
                }
                return symbols.extensionPropertyReceiverType(for: symbolID) == fileType
            })

            #expect(symbols.propertyType(for: property) == types.stringType)
        }
    }
}
#endif
