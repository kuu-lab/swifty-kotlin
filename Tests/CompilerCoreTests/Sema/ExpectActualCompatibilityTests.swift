#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExpectActualCompatibilityTests {
    private static let sharedPosSources: [String] = [
            """
            package sample0
            expect class Box<T>
            """,
            """
            package sample0
            actual class Box<T>
            """,
            """
            package sample2
            expect val platformName: String
            """,
            """
            package sample2
            actual val platformName: String = "kswift"
            """,
            """
            package sample3
            expect fun <T> identity(value: T): T
            """,
            """
            package sample3
            actual fun <T> identity(value: T): T = value
            fun useIdentity(): Int = identity(42)
            """
    ]

    private static let sharedNegSources: [String] = [
            """
            package sample1
            expect val counter: Int
            """,
            """
            package sample1
            actual var counter: Int = 0
            """,
            """
            package sample4
            interface MarkerA
            interface MarkerB
            expect class PlatformBox : MarkerA
            """,
            """
            package sample4
            interface MarkerA
            interface MarkerB
            actual class PlatformBox : MarkerB
            """
    ]

    private static nonisolated(unsafe) var _sharedPosCtx: CompilationContext?
    private static nonisolated(unsafe) var _sharedNegCtx: CompilationContext?

    private func sharedPosCtx() throws -> CompilationContext {
        if let cached = Self._sharedPosCtx { return cached }
        let ctx = makeContextFromSources(Self.sharedPosSources)
        try runSema(ctx)
        Self._sharedPosCtx = ctx
        return ctx
    }

    private func sharedNegCtx() throws -> CompilationContext {
        if let cached = Self._sharedNegCtx { return cached }
        let ctx = makeContextFromSources(Self.sharedNegSources)
        try runSema(ctx)
        Self._sharedNegCtx = ctx
        return ctx
    }

    @Test func testGenericExpectActualClassLinks() throws {
        let ctx = try sharedPosCtx()
        let errors = ctx.diagnostics.diagnostics.filter { diagnostic in
            if case .error = diagnostic.severity { return true }
            return false
        }
        #expect(errors.isEmpty, "Expected no semantic errors, got: \(errors)")

        let sema = try #require(ctx.sema)
        let fqName = [ctx.interner.intern("sample0"), ctx.interner.intern("Box")]
        let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSymbol = try #require(symbols.first { symbol in
            symbol.kind == .class && symbol.flags.contains(.expectDeclaration)
        })
        let actualSymbol = try #require(symbols.first { symbol in
            symbol.kind == .class && symbol.flags.contains(.actualDeclaration)
        })
        #expect(sema.symbols.actualSymbol(for: expectSymbol.id) == actualSymbol.id)
    }

    @Test func testExpectValPropertyMatchesActualValWithStringType() throws {
        let ctx = try sharedPosCtx()
        let errors = ctx.diagnostics.diagnostics.filter { diagnostic in
            if case .error = diagnostic.severity { return true }
            return false
        }
        #expect(errors.isEmpty, "Expected no semantic errors, got: \(errors)")

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("sample2"),
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
        let ctx = try sharedPosCtx()
        let errors = ctx.diagnostics.diagnostics.filter { diagnostic in
            if case .error = diagnostic.severity { return true }
            return false
        }
        #expect(errors.isEmpty, "Expected no semantic errors, got: \(errors)")
    }

    @Test func testExpectValDoesNotMatchActualVar() throws {
        let ctx = try sharedNegCtx()
        let errorCodes = ctx.diagnostics.diagnostics.compactMap { diagnostic -> String? in
            guard diagnostic.severity == .error else { return nil }
            return diagnostic.code
        }
        #expect(errorCodes.contains("KSWIFTK-MPP-UNRESOLVED"))
    }

    @Test func testExpectClassSupertypeMismatchIsRejected() throws {
        let ctx = try sharedNegCtx()
        let errorCodes = ctx.diagnostics.diagnostics.compactMap { diagnostic -> String? in
            guard diagnostic.severity == .error else { return nil }
            return diagnostic.code
        }
        #expect(errorCodes.contains("KSWIFTK-MPP-UNRESOLVED"))
    }
}
#endif
