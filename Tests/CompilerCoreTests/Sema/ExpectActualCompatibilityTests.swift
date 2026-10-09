#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ExpectActualCompatibilityTests {
    @Test func testImportedExpectLinksToLocalActual() throws {
        let libraryDirectory = try makeImportedExpectLibrary()
        defer { try? FileManager.default.removeItem(at: libraryDirectory) }

        try withTemporaryFile(
            contents: """
            package sample.kmp
            actual fun platformName(): Int = 7
            fun usePlatformName(): Int = platformName()
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "Platform",
                searchPaths: [libraryDirectory.path],
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let sema = try #require(ctx.sema)
            let fqName = ["sample", "kmp", "platformName"].map(ctx.interner.intern)
            let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
            let expectSymbol = try #require(symbols.first {
                $0.flags.contains(.expectDeclaration) && $0.flags.contains(.importedLibrary)
            })
            let actualSymbol = try #require(symbols.first { $0.flags.contains(.actualDeclaration) })
            #expect(sema.symbols.actualSymbol(for: expectSymbol.id) == actualSymbol.id)
            #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == actualSymbol.id })
        }
    }

    @Test func testImportedExpectWithoutLocalActualIsUnresolved() throws {
        let libraryDirectory = try makeImportedExpectLibrary()
        defer { try? FileManager.default.removeItem(at: libraryDirectory) }

        try withTemporaryFile(contents: "package sample.kmp\nfun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "Platform",
                searchPaths: [libraryDirectory.path],
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.map(\.code) == ["KSWIFTK-MPP-UNRESOLVED"], "Unexpected diagnostics: \(errors)")
        }
    }

    @Test func testOptionalExpectationDoesNotRequireActual() throws {
        let ctx = makeContextFromSource(
            """
            package sample.kmp
            @OptIn(ExperimentalMultiplatform::class)
            @OptionalExpectation
            expect annotation class JsName(val name: String)
            """
        )
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            !errors.contains { $0.code == "KSWIFTK-MPP-UNRESOLVED" },
            "Optional expect annotation classes may omit an actual declaration: \(errors)"
        )

        let sema = try #require(ctx.sema)
        let expectSymbol = try #require(sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("sample"),
            ctx.interner.intern("kmp"),
            ctx.interner.intern("JsName"),
        ]).first { sema.symbols.symbol($0)?.flags.contains(.expectDeclaration) == true })
        #expect(sema.symbols.actualSymbol(for: expectSymbol) == nil)
    }

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

    @Test func testCommonModuleFlagAllowsExpectWithoutActual() throws {
        let ctx = makeContextFromSource(
            """
            package common
            expect fun platformName(): String
            """,
            frontendFlags: ["common-module"]
        )
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Common modules may retain expect declarations: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let expectSymbol = try #require(sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("common"), ctx.interner.intern("platformName"),
        ]).compactMap { sema.symbols.symbol($0) }.first { $0.flags.contains(.expectDeclaration) })
        let record = MetadataEncoder().buildRecord(
            for: expectSymbol,
            symbols: sema.symbols,
            types: sema.types,
            moduleName: ctx.options.moduleName,
            interner: ctx.interner
        )
        let roundTripped = try #require(MetadataDecoder().decode(MetadataEncoder().serialize([record])).first)
        #expect(roundTripped.isExpect)
        #expect(!roundTripped.isActual)
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

        let sema = try #require(ctx.sema)
        for memberName in ["newEncoder", "equals"] {
            let fqName = [ctx.interner.intern("Charset"), ctx.interner.intern(memberName)]
            let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
            let expectMember = try #require(symbols.first { $0.kind == .function && $0.flags.contains(.expectDeclaration) })
            let actualMember = try #require(symbols.first { $0.kind == .function && $0.flags.contains(.actualDeclaration) })
            #expect(sema.symbols.actualSymbol(for: expectMember.id) == actualMember.id)
        }
    }

    @Test func testExpectClassMemberPropertiesLinkToActualProperties() throws {
        let ctx = makeContextFromSources([
            """
            package x
            interface IP { val cap: Int }
            expect class F1 { val p: Int }
            expect class F2 : IP { override val cap: Int }
            expect class F3(override val cap: Int) : IP
            expect abstract class F4 { abstract val p: Int }
            """,
            """
            package x
            actual class F1 { actual val p: Int = 0 }
            actual class F2 : IP { actual override val cap: Int = 0 }
            actual class F3 actual constructor(actual override val cap: Int) : IP
            actual abstract class F4 { actual val p: Int get() = 0 }
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected expect/actual member properties to pair, got: \(errors)")

        let sema = try #require(ctx.sema)
        for (className, propertyName) in [("F1", "p"), ("F2", "cap"), ("F3", "cap"), ("F4", "p")] {
            let fqName = [ctx.interner.intern("x"), ctx.interner.intern(className), ctx.interner.intern(propertyName)]
            let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
            let expectProperty = try #require(symbols.first { $0.kind == .property && $0.flags.contains(.expectDeclaration) })
            let actualProperty = try #require(symbols.first { $0.kind == .property && $0.flags.contains(.actualDeclaration) })
            #expect(sema.symbols.actualSymbol(for: expectProperty.id) == actualProperty.id)
        }
    }

    @Test func testActualAbstractFunctionMatchesExpectClassMember() throws {
        let ctx = makeContextFromSources([
            """
            expect abstract class AC { fun name(): String }
            """,
            """
            actual abstract class AC { actual abstract fun name(): String }
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let acName = [ctx.interner.intern("AC")]
        let classes = sema.symbols.lookupAll(fqName: acName).compactMap { sema.symbols.symbol($0) }
        let expectClass = try #require(classes.first { $0.flags.contains(.expectDeclaration) })
        let actualClass = try #require(classes.first { $0.flags.contains(.actualDeclaration) })
        #expect(sema.symbols.actualSymbol(for: expectClass.id) == actualClass.id)

        let methodName = acName + [ctx.interner.intern("name")]
        let methods = sema.symbols.lookupAll(fqName: methodName).compactMap { sema.symbols.symbol($0) }
        let actualMethod = try #require(methods.first { $0.flags.contains(.actualDeclaration) })
        #expect(actualMethod.flags.contains(.abstractType))
    }

    @Test func testActualFunctionInheritsAbstractnessFromExpectMember() throws {
        let ctx = makeContextFromSources([
            """
            expect abstract class AC { fun name(): String }
            """,
            """
            actual abstract class AC { actual fun name(): String }
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let methodName = [ctx.interner.intern("AC"), ctx.interner.intern("name")]
        let actualMethod = try #require(sema.symbols.lookupAll(fqName: methodName).first {
            sema.symbols.symbol($0)?.flags.contains(.actualDeclaration) == true
        })
        #expect(sema.symbols.symbol(actualMethod)?.flags.contains(.abstractType) == true)
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

    @Test func testClassConstructorCallsPreferLinkedActualOverExpect() throws {
        let ctx = makeContextFromSources([
            """
            package x
            expect open class S()
            expect open class M(message: String): Exception
            fun use() { val s = S(); val m = M("x") }
            fun useQualified() { val s = x.S(); val m = x.M("x") }
            """,
            """
            package x
            actual open class S actual constructor()
            actual open class M(message: String): Exception(message)
            typealias AliasS = S
            fun useAlias() { val s = AliasS() }
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Paired class constructors should not be ambiguous: \(errors)")

        let sema = try #require(ctx.sema)
        let constructorName = ctx.interner.intern("<init>")
        let classNames = [ctx.interner.intern("S"), ctx.interner.intern("M")]
        var expectConstructors: Set<SymbolID> = []
        var actualConstructors: Set<SymbolID> = []
        for className in classNames {
            let classFQName = [ctx.interner.intern("x"), className]
            let classSymbols = sema.symbols.lookupAll(fqName: classFQName).compactMap { sema.symbols.symbol($0) }
            let expectClass = try #require(classSymbols.first { $0.flags.contains(.expectDeclaration) })
            let actualClass = try #require(classSymbols.first { $0.flags.contains(.actualDeclaration) })
            let constructorSymbols = sema.symbols.lookupAll(fqName: classFQName + [constructorName])
            expectConstructors.formUnion(constructorSymbols.filter {
                sema.symbols.parentSymbol(for: $0) == expectClass.id
            })
            actualConstructors.formUnion(constructorSymbols.filter {
                sema.symbols.parentSymbol(for: $0) == actualClass.id
            })
        }

        let chosenConstructorCalls = sema.bindings.callBindings.values.map(\.chosenCallee).filter {
            expectConstructors.contains($0) || actualConstructors.contains($0)
        }
        #expect(expectConstructors.count == 2)
        #expect(actualConstructors.count == 2)
        #expect(chosenConstructorCalls.count == 5, "All constructor call forms should resolve: \(chosenConstructorCalls)")
        #expect(Set(chosenConstructorCalls) == actualConstructors, "Calls should bind only actual constructors: \(chosenConstructorCalls)")
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

    private func makeImportedExpectLibrary() throws -> URL {
        let libraryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kklib")
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)

        let manifest = """
        { "formatVersion": 1, "moduleName": "Common", "metadata": "metadata.bin" }
        """
        let record = MetadataRecord(
            kind: .function,
            mangledName: "common_platformName",
            fqName: "sample.kmp.platformName",
            arity: 0,
            typeSignature: "F0<I>",
            isExpect: true
        )
        let metadata = MetadataEncoder().serialize([record])
        try manifest.write(to: libraryDirectory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libraryDirectory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        return libraryDirectory
    }
}
#endif
