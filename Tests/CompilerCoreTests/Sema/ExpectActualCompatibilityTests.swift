#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExpectActualCompatibilityTests {
    @Test func testGenericExpectActualClassLinks() throws {
        let sources = [
            """
            package sample.kmp
            expect class Box<T>
            """,
            """
            package sample.kmp
            actual class Box<T>
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { diagnostic in
            if case .error = diagnostic.severity {
                return true
            }
            return false
        }
        #expect(errors.isEmpty, "Expected no semantic errors, got: \(errors)")

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("sample"),
            ctx.interner.intern("kmp"),
            ctx.interner.intern("Box")
        ]
        let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSymbol = try #require(symbols.first { symbol in
            symbol.kind == .class && symbol.flags.contains(.expectDeclaration)
        })
        let actualSymbol = try #require(symbols.first { symbol in
            symbol.kind == .class && symbol.flags.contains(.actualDeclaration)
        })

        #expect(sema.symbols.actualSymbol(for: expectSymbol.id) == actualSymbol.id)
    }

    @Test func testExpectValDoesNotMatchActualVar() throws {
        let sources = [
            """
            package sample.kmp
            expect val counter: Int
            """,
            """
            package sample.kmp
            actual var counter: Int = 0
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errorCodes = ctx.diagnostics.diagnostics.compactMap { diagnostic -> String? in
            guard diagnostic.severity == .error else {
                return nil
            }
            return diagnostic.code
        }
        let codesContain = errorCodes.contains("KSWIFTK-MPP-UNRESOLVED")
        #expect(
            codesContain,
            "Expected unresolved expect/actual mismatch, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test func testExpectClassSupertypeMismatchIsRejected() throws {
        let sources = [
            """
            package sample.kmp
            interface MarkerA
            interface MarkerB
            expect class PlatformBox : MarkerA
            """,
            """
            package sample.kmp
            interface MarkerA
            interface MarkerB
            actual class PlatformBox : MarkerB
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errorCodes = ctx.diagnostics.diagnostics.compactMap { diagnostic -> String? in
            guard diagnostic.severity == .error else {
                return nil
            }
            return diagnostic.code
        }
        let codesContain = errorCodes.contains("KSWIFTK-MPP-UNRESOLVED")
        #expect(
            codesContain,
            "Expected unresolved expect/actual mismatch, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
