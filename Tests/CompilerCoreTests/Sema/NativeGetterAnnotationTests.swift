#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeGetterAnnotationTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !(ctx.diagnostics.hasError),
                "Expected nativeGetter annotation surface to resolve cleanly, got: \(diagnostics)"
            )
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testNativeGetterAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "nativeGetter"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.nativeGetter must be registered"
        )
        let info = try #require(sema.symbols.symbol(symbol))

        #expect(info.kind == .annotationClass)
        #expect(info.visibility == .public)
        #expect(info.flags.contains(.synthetic))
    }

    @Test
    func testNativeGetterCarriesExpectedMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "nativeGetter"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let target = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "nativeGetter must carry @Target metadata"
        )
        let deprecated = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.Deprecated" },
            "nativeGetter must carry Deprecated metadata"
        )

        #expect(Set(target.arguments) == Set(["AnnotationTarget.FUNCTION"]))
        #expect(
            deprecated.arguments
            == ["message = \"Use inline extension function with body using dynamic\""]
        )
    }
}
#endif
