#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct PrimaryCtorVisibilityTests {
    @Test func testPrimaryConstructorVisibilityAndInvalidExplicitTypeArguments() throws {
        let sources = [
            """
            package test

            class Hidden private constructor()
            sealed class SealedHidden private constructor()
            class Outer {
                class Nested private constructor()
            }
            """,
            """
            package format

            fun main() {
                val text = "%s".format<String>("age")
                println(text)
            }
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        #expect(
            constructorVisibility(["test", "Hidden"], symbols: sema.symbols, interner: ctx.interner) == .private
        )
        #expect(
            constructorVisibility(["test", "SealedHidden"], symbols: sema.symbols, interner: ctx.interner) == .private
        )
        #expect(
            constructorVisibility(["test", "Outer", "Nested"], symbols: sema.symbols, interner: ctx.interner) == .private
        )

        let paths = ctx.sourceManager.fileIDs().filter { ctx.sourceManager.origin(of: $0) == .user }
        #expect(paths.count == 2)
        let formatPath = paths[1]
        let formatDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.primaryRange?.start.file == formatPath && $0.code == "KSWIFTK-SEMA-0002"
        }
        #expect(formatDiagnostics.count == 1, "Expected explicit type argument on String.format to report KSWIFTK-SEMA-0002, got: \(ctx.diagnostics.diagnostics)")

        let hiddenErrors = ctx.diagnostics.diagnostics.filter { $0.severity == .error && $0.primaryRange?.start.file == paths[0] }
        #expect(
            hiddenErrors.isEmpty,
            "Unexpected diagnostics for constructor visibility source: \(hiddenErrors.map { "\($0.code): \($0.message)" })"
        )
    }

    private func constructorVisibility(
        _ typePath: [String],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> Visibility? {
        let fqName = typePath.map(interner.intern) + [interner.intern("<init>")]
        guard let symbolID = symbols.lookup(fqName: fqName),
              let symbol = symbols.symbol(symbolID)
        else {
            return nil
        }
        return symbol.visibility
    }
}
#endif
