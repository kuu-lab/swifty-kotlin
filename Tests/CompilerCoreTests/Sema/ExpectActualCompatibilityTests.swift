#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExpectActualCompatibilityTests {
    private struct TestCase {
        let name: String
        let sources: [String]
        let assertion: (CompilationContext) throws -> Void
    }

    @Test func testExpectActualCompatibility() throws {
        let cases: [TestCase] = [
            TestCase(
                name: "genericExpectActualClassLinks",
                sources: [
                    """
                    package sample.kmp
                    expect class Box<T>
                    """,
                    """
                    package sample.kmp
                    actual class Box<T>
                    """,
                ],
                assertion: { ctx in
                    let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                    #expect(errors.isEmpty, "Expected no semantic errors, got: \(errors)")

                    let sema = try #require(ctx.sema)
                    let fqName = [
                        ctx.interner.intern("sample"),
                        ctx.interner.intern("kmp"),
                        ctx.interner.intern("Box"),
                    ]
                    let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
                    let expectSymbol = try #require(symbols.first { $0.kind == .class && $0.flags.contains(.expectDeclaration) })
                    let actualSymbol = try #require(symbols.first { $0.kind == .class && $0.flags.contains(.actualDeclaration) })
                    #expect(sema.symbols.actualSymbol(for: expectSymbol.id) == actualSymbol.id)
                }
            ),
            TestCase(
                name: "expectValDoesNotMatchActualVar",
                sources: [
                    """
                    package sample.kmp
                    expect val counter: Int
                    """,
                    """
                    package sample.kmp
                    actual var counter: Int = 0
                    """,
                ],
                assertion: { ctx in
                    let errorCodes = ctx.diagnostics.diagnostics.compactMap { diagnostic -> String? in
                        guard diagnostic.severity == .error else { return nil }
                        return diagnostic.code
                    }
                    #expect(
                        errorCodes.contains("KSWIFTK-MPP-UNRESOLVED"),
                        "Expected unresolved expect/actual mismatch, got: \(ctx.diagnostics.diagnostics)"
                    )
                }
            ),
            TestCase(
                name: "expectValPropertyMatchesActualValWithStringType",
                sources: [
                    """
                    package sample.kmp.platform
                    expect val platformName: String
                    """,
                    """
                    package sample.kmp.platform
                    actual val platformName: String = "kswift"
                    """,
                ],
                assertion: { ctx in
                    let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                    #expect(errors.isEmpty, "Expected no semantic errors, got: \(errors)")

                    let sema = try #require(ctx.sema)
                    let fqName = [
                        ctx.interner.intern("sample"),
                        ctx.interner.intern("kmp"),
                        ctx.interner.intern("platform"),
                        ctx.interner.intern("platformName"),
                    ]
                    let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
                    let expectSymbol = try #require(symbols.first { $0.kind == .property && $0.flags.contains(.expectDeclaration) })
                    let actualSymbol = try #require(symbols.first { $0.kind == .property && $0.flags.contains(.actualDeclaration) })
                    #expect(sema.symbols.actualSymbol(for: expectSymbol.id) == actualSymbol.id)
                }
            ),
            TestCase(
                name: "expectActualGenericFunctionCallIsNotAmbiguous",
                sources: [
                    """
                    package sample.kmp.funconly
                    expect fun <T> identity(value: T): T
                    """,
                    """
                    package sample.kmp.funconly
                    actual fun <T> identity(value: T): T = value
                    fun useIdentity(): Int = identity(42)
                    """,
                ],
                assertion: { ctx in
                    let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                    #expect(
                        errors.isEmpty,
                        "Expected no semantic errors (in particular no ambiguous overload), got: \(errors)"
                    )
                }
            ),
            TestCase(
                name: "expectClassSupertypeMismatchIsRejected",
                sources: [
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
                ],
                assertion: { ctx in
                    let errorCodes = ctx.diagnostics.diagnostics.compactMap { diagnostic -> String? in
                        guard diagnostic.severity == .error else { return nil }
                        return diagnostic.code
                    }
                    #expect(
                        errorCodes.contains("KSWIFTK-MPP-UNRESOLVED"),
                        "Expected unresolved expect/actual mismatch, got: \(ctx.diagnostics.diagnostics)"
                    )
                }
            ),
        ]

        for testCase in cases {
            let ctx = makeContextFromSources(testCase.sources)
            try runSema(ctx)
            try testCase.assertion(ctx)
        }
    }
}
#endif
