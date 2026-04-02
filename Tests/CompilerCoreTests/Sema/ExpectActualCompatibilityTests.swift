@testable import CompilerCore
import XCTest

final class ExpectActualCompatibilityTests: XCTestCase {
    func testGenericExpectActualFunctionLinks() throws {
        let sources = [
            """
            package sample.kmp
            expect fun <T> identity(value: T): T
            """,
            """
            package sample.kmp
            actual fun <T> identity(value: T): T = value
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
        XCTAssertTrue(errors.isEmpty, "Expected no semantic errors, got: \(errors)")

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("sample"),
            ctx.interner.intern("kmp"),
            ctx.interner.intern("identity")
        ]
        let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSymbol = try XCTUnwrap(symbols.first { symbol in
            symbol.kind == .function && symbol.flags.contains(.expectDeclaration)
        })
        let actualSymbol = try XCTUnwrap(symbols.first { symbol in
            symbol.kind == .function && symbol.flags.contains(.actualDeclaration)
        })

        XCTAssertEqual(sema.symbols.actualSymbol(for: expectSymbol.id), actualSymbol.id)
    }

    func testExpectValDoesNotMatchActualVar() throws {
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
            guard case let .error(code, _, _) = diagnostic.severity else {
                return nil
            }
            return code
        }
        XCTAssertTrue(
            errorCodes.contains("KSWIFTK-MPP-UNRESOLVED"),
            "Expected unresolved expect/actual mismatch, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testExpectClassSupertypeMismatchIsRejected() throws {
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
            guard case let .error(code, _, _) = diagnostic.severity else {
                return nil
            }
            return code
        }
        XCTAssertTrue(
            errorCodes.contains("KSWIFTK-MPP-UNRESOLVED"),
            "Expected unresolved expect/actual mismatch, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
