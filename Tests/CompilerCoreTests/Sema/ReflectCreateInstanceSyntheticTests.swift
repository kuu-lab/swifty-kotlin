#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectCreateInstanceSyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), Comment(rawValue: "Expected createInstance surface to resolve cleanly, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testCreateInstanceSurfaceIsNotRegistered() throws {
        let (sema, interner) = try makeSema()
        let functionFQName = ["kotlin", "reflect", "full", "createInstance"].map { interner.intern($0) }
        #expect(sema.symbols.lookupAll(fqName: functionFQName).isEmpty)
    }
}
#endif
