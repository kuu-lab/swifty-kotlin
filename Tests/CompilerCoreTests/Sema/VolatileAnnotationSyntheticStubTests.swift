#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct VolatileAnnotationSyntheticStubTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testVolatileAnnotationClassIsRegisteredWithFieldTarget() throws {
        let (sema, interner) = try makeSema()

        let volatileFQName = ["kotlin", "concurrent", "Volatile"].map { interner.intern($0) }
        let volatileSymbol = try #require(
            sema.symbols.lookup(fqName: volatileFQName),
            "Expected kotlin.concurrent.Volatile to be registered"
        )

        #expect(sema.symbols.symbol(volatileSymbol)?.kind == .annotationClass)
        #expect(sema.symbols.symbol(volatileSymbol)?.flags.contains(.synthetic) == true)
        #expect(
            sema.symbols.annotations(for: volatileSymbol).contains {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == ["AnnotationTarget.FIELD"]
            },
            "Expected Volatile to carry @Target(AnnotationTarget.FIELD)"
        )
    }

    @Test
    func testVolatileAnnotationResolvesInSource() throws {
        let source = """
        import kotlin.concurrent.Volatile

        class Holder {
            @Volatile
            var value: Int = 0
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected Volatile annotation to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }
}
#endif
