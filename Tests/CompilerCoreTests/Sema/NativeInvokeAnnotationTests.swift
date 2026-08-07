#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeInvokeAnnotationTests {

    @Test
    func testNativeInvokeAnnotationTestsSurfaceInventory() throws {
        let source = """
        fun noop() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testNativeInvokeAnnotationIsRegistered ===
            do {

                let fqName = ["kotlin", "js", "nativeInvoke"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "kotlin.js.nativeInvoke must be registered"
                )
                let info = try #require(sema.symbols.symbol(symbol))

                #expect(info.kind == .annotationClass)
                #expect(info.visibility == .public)
                #expect(info.flags.contains(.synthetic))
            }

            // === testNativeInvokeCarriesExpectedMetadata ===
            do {

                let fqName = ["kotlin", "js", "nativeInvoke"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                let target = try #require(
                    sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
                    "nativeInvoke must carry @Target metadata"
                )
                let deprecated = try #require(
                    sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.Deprecated" },
                    "nativeInvoke must carry Deprecated metadata"
                )

                #expect(Set(target.arguments) == Set(["AnnotationTarget.FUNCTION"]))
                #expect(
                    deprecated.arguments
                    == ["message = \"Use inline extension function with body using dynamic\""]
                )
            }
        }
    }

}
#endif
