#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ActualConstructorSupertypeCompatibilityTests {
    @Test
    func testActualConstructorKeywordPairsWhenExpectSupertypeIsPreserved() throws {
        let ctx = makeContextFromSources([
            """
            package sample.kmp
            expect interface IP
            expect open class MessageCtor(message: String): IP
            expect open class EmptyCtor(): IP
            expect open class GenericCtor<T>(value: T): IP
            expect open class HeaderCtor(message: String): IP
            expect open class NoSupertype(message: String)
            """,
            """
            package sample.kmp
            actual interface IP
            actual open class MessageCtor actual constructor(message: String): IP
            actual open class EmptyCtor actual constructor(): IP
            actual open class GenericCtor<T> actual constructor(value: T): IP
            actual open class HeaderCtor(message: String): IP
            actual open class NoSupertype actual constructor(message: String)
            """,
        ])

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected all matching expect/actual classes to pair, got: \(errors)")

        let sema = try #require(ctx.sema)
        for name in ["MessageCtor", "EmptyCtor", "GenericCtor", "HeaderCtor", "NoSupertype"] {
            let fqName = [
                ctx.interner.intern("sample"),
                ctx.interner.intern("kmp"),
                ctx.interner.intern(name),
            ]
            let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
            let expect = try #require(symbols.first { $0.flags.contains(.expectDeclaration) }, "Missing expect \(name)")
            let actual = try #require(symbols.first { $0.flags.contains(.actualDeclaration) }, "Missing actual \(name)")
            #expect(sema.symbols.actualSymbol(for: expect.id) == actual.id, "Expected \(name) to link")
        }
    }

    @Test
    func testActualConstructorSupertypeMismatchRemainsIncompatible() throws {
        let ctx = makeContextFromSources([
            """
            package sample.mismatch
            expect interface Marker
            expect interface Other
            expect class C(message: String): Marker
            """,
            """
            package sample.mismatch
            actual interface Marker
            actual interface Other
            actual class C actual constructor(message: String): Other
            """,
        ])

        try runSema(ctx)

        let errorCodes = ctx.diagnostics.diagnostics.compactMap { diagnostic -> String? in
            guard diagnostic.severity == .error else { return nil }
            return diagnostic.code
        }
        #expect(
            errorCodes.contains("KSWIFTK-MPP-UNRESOLVED"),
            "The actual constructor spelling must not make a different supertype compatible: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
