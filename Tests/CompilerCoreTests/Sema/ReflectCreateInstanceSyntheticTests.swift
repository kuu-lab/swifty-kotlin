#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectCreateInstanceSyntheticTests {
    private static let fixture = SemaFixture(surface: "createInstance")

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        try Self.fixture.shared()
    }

    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        try Self.fixture.make(source: source)
    }

    @Test func testCreateInstanceSurfaceIsNotRegistered() throws {
        let (sema, interner) = try sharedSema()
        let functionFQName = ["kotlin", "reflect", "full", "createInstance"].map { interner.intern($0) }
        #expect(sema.symbols.lookupAll(fqName: functionFQName).isEmpty)
    }
}
#endif
