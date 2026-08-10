#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectCreateInstanceSyntheticTests {

    @Test
    func testReflectCreateInstanceSyntheticTestsInventory() throws {
        let sources: [String] = [
            """
            fun noop() {}
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testCreateInstanceSurfaceIsNotRegistered ===
            do {

                let functionFQName = ["kotlin", "reflect", "full", "createInstance"].map { interner.intern($0) }
                #expect(sema.symbols.lookupAll(fqName: functionFQName).isEmpty)
            }
        }
    }

}
#endif
