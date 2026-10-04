#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKClassCastSyntheticTests {
    private static let fixture = SemaFixture(surface: "KClass.cast")

    private func makeSema(
        source: String = "fun noop() {}",
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) throws -> (SemaModule, StringInterner) {
        try Self.fixture.make(source: source, sourceLocation: sourceLocation)
    }

    @Test func testKClassCastInfersReceiverArgumentReturnTypes() throws {
        let source = """
        import kotlin.reflect.KClass

        fun castString(value: Any?): String = String::class.cast(value)

        fun castViaLocal(value: Any?): String {
            val klass = String::class
            return klass.cast(value)
        }

        fun <T : Any> castWithClass(klass: KClass<T>, value: Any?): T = klass.cast(value)
        """
        let (sema, interner) = try makeSema(source: source)

        for functionName in ["castString", "castViaLocal"] {
            let symbol = try #require(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(
                signature.returnType == sema.types.stringType,
                Comment(rawValue: "\(functionName) should infer String from KClass<String>.cast")
            )
        }

        let genericSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("castWithClass")]))
        let genericSignature = try #require(sema.symbols.functionSignature(for: genericSymbol))
        if case .typeParam = sema.types.kind(of: genericSignature.returnType) {
            // Expected: generic KClass<T>.cast preserves T.
        } else {
            Issue.record("Expected generic KClass.cast wrapper to return T")
        }
    }
}
#endif
