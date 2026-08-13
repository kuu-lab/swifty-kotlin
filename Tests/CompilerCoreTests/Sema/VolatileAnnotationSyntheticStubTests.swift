#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct VolatileAnnotationSyntheticStubTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        import kotlin.concurrent.Volatile

        class Holder {
            @Volatile
            var value: Int = 0
        }
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    @Test
    func testVolatileAnnotationClassIsRegisteredWithFieldTarget() throws {
        let (sema, interner) = try sharedSema()

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

    @Test func testVolatileAnnotationResolvesInSource() throws {

        let ctx = try sharedCtx()
            #expect(!(ctx.diagnostics.hasError), "Expected Volatile annotation to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

    }
}
#endif
