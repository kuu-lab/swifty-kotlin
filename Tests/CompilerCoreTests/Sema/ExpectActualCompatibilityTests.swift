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

    @Test func testExpectValPropertyMatchesActualValWithStringType() throws {
        // Regression for a bug where `TypeKind.stringStruct` (the dedicated
        // representation for `kotlin.String`) was missing from
        // `expectActualTypesMatch`'s switch, so any expect/actual property
        // typed `String` fell through to the `default: return false` case
        // even though both sides resolved to the exact same type.
        let sources = [
            """
            package sample.kmp.platform
            expect val platformName: String
            """,
            """
            package sample.kmp.platform
            actual val platformName: String = "kswift"
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
            ctx.interner.intern("platform"),
            ctx.interner.intern("platformName"),
        ]
        let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSymbol = try #require(symbols.first { symbol in
            symbol.kind == .property && symbol.flags.contains(.expectDeclaration)
        })
        let actualSymbol = try #require(symbols.first { symbol in
            symbol.kind == .property && symbol.flags.contains(.actualDeclaration)
        })
        #expect(sema.symbols.actualSymbol(for: expectSymbol.id) == actualSymbol.id)
    }

    @Test func testExpectActualGenericFunctionCallIsNotAmbiguous() throws {
        // Regression for a bug where an expect/actual pair sharing an identical
        // signature (e.g. `identity<T>`) both remained visible as call
        // candidates in the same scope. Since neither was more specific than
        // the other, overload resolution found zero winners and reported a
        // false "KSWIFTK-SEMA-0003 Ambiguous overload resolution" at any call
        // site, even though only one implementation actually exists at runtime.
        let sources = [
            """
            package sample.kmp.funconly
            expect fun <T> identity(value: T): T
            """,
            """
            package sample.kmp.funconly
            actual fun <T> identity(value: T): T = value
            fun useIdentity(): Int = identity(42)
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
        #expect(errors.isEmpty, "Expected no semantic errors (in particular no ambiguous overload), got: \(errors)")
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
