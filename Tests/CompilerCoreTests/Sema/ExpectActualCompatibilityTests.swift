#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExpectActualCompatibilityTests {
    @Test func testExpectClassBodylessMembersOnlyReportMissingActual() throws {
        let ctx = makeContextFromSource(
            """
            expect abstract class Charset {
                fun newEncoder(): Int
                final override fun equals(other: Any?): Boolean
            }
            """
        )
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty)
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-MPP-UNRESOLVED" }, "Unexpected diagnostics: \(errors)")
    }

    @Test func testExpectActualObjectLinksWithoutDuplicateDeclaration() throws {
        let ctx = makeContextFromSources([
            """
            expect object O
            """,
            """
            actual object O
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let symbols = sema.symbols.lookupAll(fqName: [ctx.interner.intern("O")])
            .compactMap { sema.symbols.symbol($0) }
        let expectSymbol = try #require(symbols.first { $0.flags.contains(.expectDeclaration) })
        let actualSymbol = try #require(symbols.first { $0.flags.contains(.actualDeclaration) })
        #expect(sema.symbols.actualSymbol(for: expectSymbol.id) == actualSymbol.id)
    }

    @Test func testExpectClassBodylessMembersLinkToActual() throws {
        let ctx = makeContextFromSources([
            """
            expect abstract class Charset {
                fun newEncoder(): Int
                final override fun equals(other: Any?): Boolean
            }
            """,
            """
            actual abstract class Charset {
                actual fun newEncoder(): Int = 1
                actual final override fun equals(other: Any?): Boolean = false
            }
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")
    }

    @Test func testNonExpectClassBodylessMembersStillRequireBodies() throws {
        let ctx = makeContextFromSource(
            """
            abstract class Charset {
                fun newEncoder(): Int
                final override fun equals(other: Any?): Boolean
            }
            """
        )
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 2, "Expected a missing-body error for each member: \(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0009" }, "Unexpected diagnostics: \(errors)")
    }

    @Test func testUnresolvedExpectExtensionRemainsCallable() throws {
        let ctx = makeContextFromSource(
            """
            package sample.kmp
            expect fun Short.reverseByteOrder(): Short
            fun fromShort(value: Short): Short = value.reverseByteOrder()
            fun UShort.rb(): UShort = toShort().reverseByteOrder().toUShort()
            """
        )
        try runSema(ctx)

        // Missing actual is diagnosed independently of overload resolution.
        // Both member-style calls must still bind the expect declaration.
        let codes = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.compactMap(\.code)
        #expect(codes.contains("KSWIFTK-MPP-UNRESOLVED"))
        #expect(!codes.contains("KSWIFTK-SEMA-0002"), "Expect extension must be a viable call candidate: \(ctx.diagnostics.diagnostics)")
        #expect(!codes.contains("KSWIFTK-SEMA-0003"), "Expect extension must not become ambiguous: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let expectSymbol = try #require(sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("sample"), ctx.interner.intern("kmp"), ctx.interner.intern("reverseByteOrder"),
        ]).first { sema.symbols.symbol($0)?.flags.contains(.expectDeclaration) == true })
        let resolvedCalls = sema.bindings.callBindings.values.filter { $0.chosenCallee == expectSymbol }
        #expect(resolvedCalls.count == 2, "Both member-style calls must bind the expect declaration")
    }

    @Test func testMemberCallPrefersLinkedActualOverExpect() throws {
        let ctx = makeContextFromSources([
            """
            package sample.kmp
            expect fun Short.reverseByteOrder(): Short
            """,
            """
            package sample.kmp
            actual fun Short.reverseByteOrder(): Short = this
            fun fromShort(value: Short): Short = value.reverseByteOrder()
            fun UShort.rb(): UShort = toShort().reverseByteOrder().toUShort()
            """,
        ])
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Linked actual must resolve both calls without ambiguous overloads: \(errors)")

        let sema = try #require(ctx.sema)
        let actualSymbol = try #require(sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("sample"), ctx.interner.intern("kmp"), ctx.interner.intern("reverseByteOrder"),
        ]).first { sema.symbols.symbol($0)?.flags.contains(.actualDeclaration) == true })
        #expect(sema.bindings.callBindings.values.filter { $0.chosenCallee == actualSymbol }.count == 2)
    }

    @Test func testSubclassInheritsActualClassLayoutWhenExpectAndActualShareModule() throws {
        let ctx = makeContextFromSource(
            """
            expect abstract class Pool<T : Any>(capacity: Int) {
                protected abstract fun produce(): T
                protected open fun disposeInstance(instance: T)
                fun borrow(): T
            }

            actual abstract class Pool<T : Any> actual constructor(capacity: Int) {
                protected actual abstract fun produce(): T
                protected actual open fun disposeInstance(instance: T) {}
                actual fun borrow(): T = produce()
            }

            class IntPool : Pool<Int>(1) {
                override fun produce(): Int = 42
            }
            """
        )
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let fqName = [ctx.interner.intern("Pool")]
        let poolSymbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSymbol = try #require(poolSymbols.first { $0.flags.contains(.expectDeclaration) })
        let actualSymbol = try #require(poolSymbols.first { $0.flags.contains(.actualDeclaration) })
        let intPoolSymbol = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("IntPool")]).first)
        let produceFQName = fqName + [ctx.interner.intern("produce")]
        let actualProduce = try #require(sema.symbols.lookupAll(fqName: produceFQName).first {
            sema.symbols.symbol($0)?.flags.contains(.actualDeclaration) == true
        })
        let intPoolProduce = try #require(sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("IntPool"), ctx.interner.intern("produce"),
        ]).first)
        let expectLayout = try #require(sema.symbols.nominalLayout(for: expectSymbol.id))
        let actualLayout = try #require(sema.symbols.nominalLayout(for: actualSymbol.id))
        let intPoolLayout = try #require(sema.symbols.nominalLayout(for: intPoolSymbol))

        #expect(sema.symbols.directSupertypes(for: intPoolSymbol).contains(actualSymbol.id))
        #expect(!sema.symbols.directSupertypes(for: intPoolSymbol).contains(expectSymbol.id))
        #expect(expectLayout.vtableSize == 3)
        #expect(actualLayout.vtableSize == 3)
        #expect(actualLayout.vtableSlots[actualProduce] == intPoolLayout.vtableSlots[intPoolProduce])
    }

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
