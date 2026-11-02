#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ExpectActualCompatibilityTests {
    @Test
    func genericExpectFactoryResultRetainsMutablePropertySetter() throws {
        let ctx = makeContextFromSources([
            """
            package sample.kmp
            expect class AtomicRef<T>(initial: T) { var value: T }
            expect fun <T> atomic(initial: T): AtomicRef<T>
            fun updateOwner() {
                val owner = atomic<String?>(null)
                owner.value = "owner"
                val direct = AtomicRef<String?>(null)
                direct.value = "direct"
            }
            """,
            """
            package sample.kmp
            actual class AtomicRef<T> actual constructor(initial: T) {
                actual var value: T = initial
            }
            actual fun <T> atomic(initial: T): AtomicRef<T> = error("stub")
            """,
        ])

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics for a mutable expect property: \(errors)")
    }

    @Test(arguments: [false, true])
    func testImportedExpectLinksToLocalActual(indexed: Bool) throws {
        let libraryDirectory = try makeImportedExpectLibrary(indexed: indexed)
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

    @Test(arguments: [false, true])
    func testImportedExpectWithoutLocalActualIsUnresolved(indexed: Bool) throws {
        let libraryDirectory = try makeImportedExpectLibrary(indexed: indexed)
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

    @Test func testOptionalExpectationMembersDoNotSuppressUnrelatedExpectRequirement() throws {
        let ctx = makeContextFromSource(
            """
            package sample.kmp
            @OptIn(ExperimentalMultiplatform::class)
            @OptionalExpectation
            expect annotation class OptionalTag(val name: String)
            expect fun requiredPlatformValue(): Int
            """
        )
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.map(\.code) == ["KSWIFTK-MPP-UNRESOLVED"], "Unexpected diagnostics: \(errors)")
        #expect(errors.first?.message.contains("sample.kmp.requiredPlatformValue") == true)
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

    @Test func testExpectClassCompanionBodylessMembersOnlyReportMissingActual() throws {
        try withTemporaryFile(
            contents: """
            interface Sink
            expect class HashingSink : Sink {
                companion object {
                    fun md5(sink: Sink): HashingSink
                }
            }
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Expect class companion members are contracts in common modules: \(ctx.diagnostics.diagnostics)"
            )
        }
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

    @Test func testExpectClassCanBeImplementedByActualTypealias() throws {
        try withSemaContextFromSourcesWithoutStdlib([
            try repositoryFileSource("Tests/CompilerCoreTests/Fixtures/KUU-2415/common/Synchronized.kt"),
            try repositoryFileSource("Tests/CompilerCoreTests/Fixtures/KUU-2415/posix/Synchronized.kt"),
            """
            package io.ktor.utils.io.locks
            fun exerciseLockMembers(lock: ReentrantLock): Boolean {
                lock.lock()
                val acquired = lock.tryLock()
                lock.unlock()
                return acquired
            }
            """,
        ]) { ctx in
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            let sema = try #require(ctx.sema)

            let reentrantLockFQName = [
                "io", "ktor", "utils", "io", "locks", "ReentrantLock",
            ].map(ctx.interner.intern)
            let reentrantLockSymbols = sema.symbols.lookupAll(fqName: reentrantLockFQName)
                .compactMap { sema.symbols.symbol($0) }
            let expectSymbol = try #require(reentrantLockSymbols.first { $0.flags.contains(.expectDeclaration) })
            let actualAlias = try #require(reentrantLockSymbols.first {
                $0.kind == .typeAlias && $0.flags.contains(.actualDeclaration)
            })
            #expect(sema.symbols.actualSymbol(for: expectSymbol.id) == actualAlias.id)

            let synchronizedObjectFQName = [
                "io", "ktor", "utils", "io", "locks", "SynchronizedObject",
            ].map(ctx.interner.intern)
            let synchronizedObjectSymbol = try #require(
                sema.symbols.lookupAll(fqName: synchronizedObjectFQName).compactMap { sema.symbols.symbol($0) }
                    .first { $0.flags.contains(.actualDeclaration) }
            )
            #expect(errors.isEmpty, "Expected the actual typealias and its members to resolve, got: \(errors)")
            let actualMemberIDs = Dictionary(uniqueKeysWithValues: ["lock", "tryLock", "unlock"].compactMap { name in
                sema.symbols.lookupAll(fqName: synchronizedObjectFQName + [ctx.interner.intern(name)])
                    .first { sema.symbols.parentSymbol(for: $0) == synchronizedObjectSymbol.id }
                    .map { (name, $0) }
            })

            for (name, actualMemberID) in actualMemberIDs {
                let expectMemberID = try #require(
                    sema.symbols.lookupAll(fqName: reentrantLockFQName + [ctx.interner.intern(name)])
                        .first { sema.symbols.parentSymbol(for: $0) == expectSymbol.id }
                )
                #expect(sema.symbols.actualSymbol(for: expectMemberID) == actualMemberID)
            }

            let boundCallees = Set(sema.bindings.callBindings.values.map(\.chosenCallee))
            #expect(Set(actualMemberIDs.values).isSubset(of: boundCallees))
        }
    }

    @Test func testExpectClassActualTypealiasRejectsMissingUnderlyingMembers() throws {
        try withSemaContextFromSourcesWithoutStdlib([
            """
            package sample.kmp
            expect class ReentrantLock {
                fun lock()
                fun unlock()
            }
            """,
            """
            package sample.kmp
            class UnderlyingLock {
                fun lock() {}
            }
            actual typealias ReentrantLock = UnderlyingLock
            """,
        ]) { ctx in
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.contains { $0.code == "KSWIFTK-MPP-UNRESOLVED" && $0.message.contains("ReentrantLock.unlock") },
                "Expected a missing actual member diagnostic, got: \(errors)"
            )
        }
    }

    @Test func testExpectClassActualTypealiasRejectsNonClassUnderlyingType() throws {
        try withSemaContextFromSourcesWithoutStdlib([
            """
            package sample.kmp
            expect class ReentrantLock
            """,
            """
            package sample.kmp
            actual typealias ReentrantLock = () -> Int
            """,
        ]) { ctx in
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.contains { $0.code == "KSWIFTK-MPP-UNRESOLVED" },
                "Expected an incompatible actual typealias diagnostic, got: \(errors)"
            )
        }
    }

    private func withSemaContextFromSourcesWithoutStdlib(
        _ sources: [String],
        body: (CompilationContext) throws -> Void
    ) throws {
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            try body(ctx)
        }
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
            // kotlinc forbids property parameters on expect constructors — the
            // actual supplies the `val`, so the expect side takes a plain param.
            expect class F3(cap: Int) : IP
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
        // F3 pairs its constructor by plain parameter — the `cap` property only
        // exists on the actual declaration, so there is no expect member to link.
        for (className, propertyName) in [("F1", "p"), ("F2", "cap"), ("F4", "p")] {
            let fqName = [ctx.interner.intern("x"), ctx.interner.intern(className), ctx.interner.intern(propertyName)]
            let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
            let expectProperty = try #require(symbols.first { $0.kind == .property && $0.flags.contains(.expectDeclaration) })
            let actualProperty = try #require(symbols.first { $0.kind == .property && $0.flags.contains(.actualDeclaration) })
            #expect(sema.symbols.actualSymbol(for: expectProperty.id) == actualProperty.id)
        }
    }

    /// KUU-3887: an override targeting a member of an expect/actual paired
    /// class must be judged against the actual declaration — the expect side
    /// carries no `open`/`abstract` information. This runs at header time,
    /// before `setExpectActualLink`, so the check pairs the declarations
    /// positionally.
    @Test func testSubclassOverrideThroughPairedActualClass() throws {
        let ctx = makeContextFromSources([
            """
            package x
            interface Pool<T> { fun borrow(): T }
            // Plain ctor param — kotlinc forbids `val`/`var` on expect ctors.
            expect abstract class DP<T : Any>(capacity: Int) : Pool<T> {
                protected fun produce(): T
            }
            """,
            """
            package x
            actual abstract class DP<T : Any>(actual val capacity: Int) : Pool<T> {
                protected actual open fun produce(): T = TODO()
                actual override fun borrow(): T = produce()
            }
            class Sub : DP<Int>(8) { override fun produce(): Int = 1 }
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected override through expect/actual pair to judge the actual member, got: \(errors)")
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

    @Test func testExpectActualEnumEntriesAndCompanionMembersPair() throws {
        let ctx = makeContextFromSources([
            """
            package x
            expect enum class ByteOrder {
                BIG_ENDIAN, LITTLE_ENDIAN;
                companion object { fun nativeOrder(): ByteOrder }
            }
            """,
            """
            package x
            actual enum class ByteOrder {
                BIG_ENDIAN, LITTLE_ENDIAN;
                actual companion object { actual fun nativeOrder(): ByteOrder = LITTLE_ENDIAN }
            }
            fun useNativeOrder(): ByteOrder = ByteOrder.nativeOrder()
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let enumFQName = [ctx.interner.intern("x"), ctx.interner.intern("ByteOrder")]
        let enumSymbols = sema.symbols.lookupAll(fqName: enumFQName).compactMap { sema.symbols.symbol($0) }
        let expectEnum = try #require(enumSymbols.first { $0.flags.contains(.expectDeclaration) })
        let actualEnum = try #require(enumSymbols.first { $0.flags.contains(.actualDeclaration) })
        #expect(sema.symbols.actualSymbol(for: expectEnum.id) == actualEnum.id)

        let expectCompanion = try #require(sema.symbols.companionObjectSymbol(for: expectEnum.id))
        let actualCompanion = try #require(sema.symbols.companionObjectSymbol(for: actualEnum.id))
        let nativeOrderFQName = enumFQName + [ctx.interner.intern("Companion"), ctx.interner.intern("nativeOrder")]
        let nativeOrderSymbols = sema.symbols.lookupAll(fqName: nativeOrderFQName).compactMap { sema.symbols.symbol($0) }
        let expectNativeOrder = try #require(nativeOrderSymbols.first { $0.flags.contains(.expectDeclaration) })
        let actualNativeOrder = try #require(nativeOrderSymbols.first { $0.flags.contains(.actualDeclaration) })
        #expect(sema.symbols.parentSymbol(for: expectNativeOrder.id) == expectCompanion)
        #expect(sema.symbols.parentSymbol(for: actualNativeOrder.id) == actualCompanion)
        #expect(sema.symbols.actualSymbol(for: expectNativeOrder.id) == actualNativeOrder.id)
        #expect(
            sema.bindings.callBindings.values.contains { $0.chosenCallee == actualNativeOrder.id },
            "A class-name call on an expect/actual enum must bind to the actual companion member"
        )

        for entryName in ["BIG_ENDIAN", "LITTLE_ENDIAN"] {
            let entrySymbols = sema.symbols.lookupAll(fqName: enumFQName + [ctx.interner.intern(entryName)])
                .compactMap { sema.symbols.symbol($0) }
            let expectEntry = try #require(entrySymbols.first { $0.flags.contains(.expectDeclaration) })
            let actualEntry = try #require(entrySymbols.first { $0.flags.contains(.actualDeclaration) })
            #expect(sema.symbols.actualSymbol(for: expectEntry.id) == actualEntry.id)
        }
    }

    @Test func testClassNameCallResolvesCompanionAddedByActual() throws {
        let ctx = makeContextFromSources([
            """
            package x
            expect abstract class Charset
            """,
            """
            package x
            actual abstract class Charset {
                companion object {
                    fun forName(name: String): Charset = throw Exception(name)
                }
            }
            fun lookup(name: String): Charset = Charset.forName(name)
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Actual-only companion members must resolve through the expect class: \(errors)")

        let sema = try #require(ctx.sema)
        let actualMethod = try #require(sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("x"), ctx.interner.intern("Charset"),
            ctx.interner.intern("Companion"), ctx.interner.intern("forName"),
        ]).first { sema.symbols.symbol($0)?.flags.contains(.actualDeclaration) == false })
        #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == actualMethod })
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

    @Test func testActualFunctionCanConstructItsLinkedClassReturnType() throws {
        let ctx = makeContextFromSources([
            """
            package sample.kmp
            expect class RL { fun lock() }
            expect fun mk(): RL
            """,
            """
            package sample.kmp
            actual class RL { actual fun lock() {} }
            actual fun mk(): RL = RL()
            fun u(): RL = RL()
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Paired class construction should satisfy the actual function return type: \(errors)")

        let sema = try #require(ctx.sema)
        let classFQName = [ctx.interner.intern("sample"), ctx.interner.intern("kmp"), ctx.interner.intern("RL")]
        let classSymbols = sema.symbols.lookupAll(fqName: classFQName).compactMap { sema.symbols.symbol($0) }
        let expectClass = try #require(classSymbols.first { $0.flags.contains(.expectDeclaration) })
        let actualClass = try #require(classSymbols.first { $0.flags.contains(.actualDeclaration) })
        let expectType = sema.types.make(.classType(ClassType(classSymbol: expectClass.id, args: [], nullability: .nonNull)))
        let actualType = sema.types.make(.classType(ClassType(classSymbol: actualClass.id, args: [], nullability: .nonNull)))
        #expect(sema.types.isSubtype(expectType, actualType))
        #expect(sema.types.isSubtype(actualType, expectType))
    }

    @Test func testTopLevelInitializerFlowsIntoLinkedActualReturnType() throws {
        let ctx = makeContextFromSources([
            """
            package sample.kmp
            expect class RL
            expect fun mk(): RL
            """,
            """
            package sample.kmp
            actual class RL
            private val shared = RL()
            actual fun mk(): RL = shared
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "A value of the paired actual class should satisfy the linked return type: \(errors)")
    }

    @Test func testGenericActualCallAcceptsLinkedClassArgument() throws {
        let ctx = makeContextFromSources([
            """
            package sample.kmp
            expect open class S()
            expect inline fun <T> synchronized(lock: S, block: () -> T): T
            """,
            """
            package sample.kmp
            actual open class S()
            actual inline fun <T> synchronized(lock: S, block: () -> T): T = block()
            fun use(): Int {
                val m = S()
                return synchronized(m) { 42 }
            }
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "An actual class value should satisfy the paired generic function parameter: \(errors)")
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
        let sources: [String]
        let assertion: (CompilationContext) throws -> Void
    }

    @Test func testExpectActualCompatibility() throws {
        let cases: [TestCase] = [
            TestCase(
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

    /// KUU-3774: members nested inside an `expect class` body are expected
    /// implicitly — companion-object properties need no initializer.
    @Test func testExpectClassCompanionObjectPropertiesNeedNoInitializer() throws {
        try withTemporaryFile(
            contents: """
            expect class E {
                companion object {
                    val ZERO: E
                    internal val MIN: E
                }
            }
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                !errors.contains { $0.code == "KSWIFTK-SEMA-0424" },
                "Companion-object properties of an expect class declare contracts only: \(errors)"
            )
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    /// KUU-3774: a secondary constructor inside an `expect class` is a
    /// bodiless declaration — the actual supplies the delegation call.
    @Test func testExpectClassSecondaryConstructorNeedsNoDelegation() throws {
        try withTemporaryFile(
            contents: """
            expect class E(x: Int) {
                constructor()
            }
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                !errors.contains { $0.code == "KSWIFTK-SEMA-0054" },
                "Expect-class secondary constructors are bodiless declarations: \(errors)"
            )
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    /// KUU-3774: the expect exemption propagates through nested nominal
    /// members — a class/object nested inside an `expect class` declares
    /// signatures only.
    @Test func testNestedTypeMembersInsideExpectClassNeedNoImplementation() throws {
        try withTemporaryFile(
            contents: """
            expect class E {
                class N { val x: Int }
                object O { val y: Int }
                class C(x: Int) { constructor() }
            }
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                !errors.contains { $0.code == "KSWIFTK-SEMA-0424" || $0.code == "KSWIFTK-SEMA-0054" },
                "Members of nested types inside an expect class are also contracts: \(errors)"
            )
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    /// KUU-3774: the propagated expect context keeps kotlinc's positive
    /// diagnostics — implementations inside an expect companion still fail.
    @Test func testExpectClassCompanionMemberBodiesAreStillDiagnosed() throws {
        try withTemporaryFile(
            contents: """
            expect class E {
                companion object {
                    val x: Int = 0
                    fun f() {}
                }
            }
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            let codes = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.code)
            #expect(
                codes.contains("KSWIFTK-SEMA-0453"),
                "Expected 'expect' initializer diagnostic: \(ctx.diagnostics.diagnostics)"
            )
            #expect(
                codes.contains("KSWIFTK-SEMA-0452"),
                "Expected 'expect' body diagnostic: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    /// KUU-3930: the okio shape — mutable (`var`) and annotated (`@JvmField`)
    /// members of a nested class inside an `expect class` need no
    /// initializer either, at any nesting depth.
    @Test func testNestedClassVarMembersInsideExpectClassNeedNoInitializer() throws {
        try withTemporaryFile(
            contents: """
            interface Closeable { fun close() }
            class Segment
            expect class Buffer {
                internal var head: Segment?
                var size: Long
                    internal set

                class UnsafeCursor constructor() : Closeable {
                    @JvmField var buffer: Buffer?
                    @JvmField var readWrite: Boolean
                    internal var segment: Segment?
                    @JvmField var offset: Long
                    val data: ByteArray?
                    fun next(): Int
                    override fun close()

                    class Deeper { val x: Int }
                }
            }
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                !errors.contains { $0.code == "KSWIFTK-SEMA-0424" },
                "Nested-class members inside an expect class are contracts too: \(errors)"
            )
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    /// KUU-3921: an `actual` member may omit its type annotation when the
    /// initializer pins the type — the kotlinx-datetime
    /// `LocalDate.Companion.MIN/MAX` shape. The header placeholder must not
    /// fail matching, and the provisional link is re-verified once body
    /// analysis publishes the inferred type.
    @Test func testActualCompanionPropertiesWithInferredTypesMatchExpect() throws {
        try withSemaContextFromSourcesWithoutStdlib([
            """
            expect class LocalDate {
                companion object {
                    internal val MIN: LocalDate
                    internal val MAX: LocalDate
                }
            }
            """,
            """
            actual class LocalDate {
                actual companion object {
                    internal actual val MIN = LocalDate()
                    internal actual val MAX = LocalDate()
                }
            }
            """,
        ]) { ctx in
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Inferred-type actual members must satisfy their expect contracts: \(errors)"
            )

            let sema = try #require(ctx.sema)
            let fqName = ["LocalDate", "Companion", "MIN"].map(ctx.interner.intern)
            let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
            let expectSymbol = try #require(symbols.first { $0.flags.contains(.expectDeclaration) })
            let actualSymbol = try #require(symbols.first { $0.flags.contains(.actualDeclaration) })
            #expect(sema.symbols.actualSymbol(for: expectSymbol.id) == actualSymbol.id)
        }
    }

    /// KUU-3921: the same placeholder problem hits top-level/member
    /// properties and expression-bodied functions whose actual side leaves
    /// the type or return type to inference.
    @Test func testInferredActualMembersMatchExpectDeclarations() throws {
        try withSemaContextFromSourcesWithoutStdlib([
            """
            expect val topX: Int
            expect class Foo {
                val memberX: Int
            }
            expect fun topF(): Int
            """,
            """
            actual val topX = 1
            actual class Foo {
                actual val memberX = 1
            }
            actual fun topF() = 1
            """,
        ]) { ctx in
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Inferred actual types must not trip expect/actual matching: \(errors)"
            )
        }
    }

    /// KUU-3921: the deferral is provisional — a genuinely mismatched
    /// inferred actual type is still rejected once body analysis publishes
    /// the real type.
    @Test func testInferredActualTypeMismatchIsStillDiagnosed() throws {
        try withSemaContextFromSourcesWithoutStdlib([
            """
            expect val topX: Int
            expect fun topF(): Int
            """,
            """
            actual val topX = "str"
            actual fun topF() = 1.5
            """,
        ]) { ctx in
            let errorCodes = ctx.diagnostics.diagnostics.compactMap { diagnostic -> String? in
                guard diagnostic.severity == .error else { return nil }
                return diagnostic.code
            }
            #expect(
                errorCodes.filter { $0 == "KSWIFTK-MPP-UNRESOLVED" }.count == 2,
                "Expected an unresolved diagnostic per mismatched inferred actual: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    /// KUU-3774: `actual` members are real implementations — the expect
    /// exemption must not leak into the actual side of the pair.
    @Test func testActualCompanionPropertyStillRequiresInitializer() throws {
        try withSemaContextFromSourcesWithoutStdlib([
            """
            expect class E {
                companion object {
                    val ZERO: E
                }
            }
            """,
            """
            actual class E {
                actual companion object {
                    actual val ZERO: E
                }
            }
            """,
        ]) { ctx in
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.contains { $0.code == "KSWIFTK-SEMA-0424" },
                "Actual companion properties still need an initializer: \(errors)"
            )
        }
    }

    /// KUU-3898: kotlinc rejects `val`/`var` parameters in `expect` class
    /// constructors — the actual declaration supplies the properties.
    @Test func testExpectClassConstructorPropertyParameterIsRejected() throws {
        try withTemporaryFile(
            contents: """
            expect class E(val x: Int, var y: Int)
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            // The diagnostic engine dedupes identical diagnostics, so multiple
            // property params collapse to a single constructor-level error.
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.contains { $0.code == "KSWIFTK-SEMA-0456" },
                "Property parameters on an expect class constructor are diagnosed: \(errors)"
            )
        }
    }

    /// KUU-3898: a plain (non-property) constructor parameter stays legal —
    /// only `val`/`var` parameters are prohibited.
    @Test func testExpectClassConstructorPlainParameterIsAccepted() throws {
        try withTemporaryFile(
            contents: """
            expect class E(x: Int)
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                !errors.contains { $0.code == "KSWIFTK-SEMA-0456" },
                "Non-property expect constructor parameters are legal: \(errors)"
            )
        }
    }

    /// KUU-3898: `expect` classes — including `expect object` declarations —
    /// cannot initialize supertypes; the actual supplies the `super(...)` call.
    @Test func testExpectDeclarationSupertypeInitializationIsRejected() throws {
        try withTemporaryFile(
            contents: """
            interface I
            expect class H : I()
            expect object O : I()
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.filter { $0.code == "KSWIFTK-SEMA-0457" }.count == 2,
                "Expect class and object supertype calls are diagnosed: \(errors)"
            )
        }
    }

    /// KUU-3898: an `expect enum class` cannot declare a constructor — its
    /// `val` parameters and the entries' `(...)` arguments are diagnosed too.
    @Test func testExpectEnumClassConstructorIsRejected() throws {
        try withTemporaryFile(
            contents: """
            expect enum class En(val v: Int) { A(1), B }
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.contains { $0.code == "KSWIFTK-SEMA-0458" },
                "Expect enum class with a constructor is diagnosed: \(errors)"
            )
            #expect(
                errors.contains { $0.code == "KSWIFTK-SEMA-0456" },
                "The enum constructor's property parameter is diagnosed: \(errors)"
            )
            #expect(
                errors.filter { $0.code == "KSWIFTK-SEMA-0457" }.count == 1,
                "Only the entry writing `(...)` is a supertype initialization site: \(errors)"
            )
        }
    }

    /// KUU-3898: any enum-entry body — including an empty `{}` — is prohibited
    /// inside an expect enum, while a bare entry stays legal.
    @Test func testExpectEnumEntryBodyIsRejected() throws {
        try withTemporaryFile(
            contents: """
            expect enum class E {
                A { val x: Int },
                B { },
                C
            }
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.filter { $0.code == "KSWIFTK-SEMA-0459" }.count == 2,
                "Both `A { ... }` and `B {}` are diagnosed but not `C`: \(errors)"
            )
        }
    }

    /// KUU-3898: members of an `expect` owner are implicitly expect — nested
    /// enum/class declarations obey the same shape rules.
    @Test func testExpectShapeRulesPropagateToImplicitExpectMembers() throws {
        try withTemporaryFile(
            contents: """
            expect class O {
                enum class En { A { } }
                class N(val x: Int)
            }
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.contains { $0.code == "KSWIFTK-SEMA-0459" },
                "Entry bodies inside an implicitly-expect enum are diagnosed: \(errors)"
            )
            #expect(
                errors.contains { $0.code == "KSWIFTK-SEMA-0456" },
                "Property parameters inside an implicitly-expect class are diagnosed: \(errors)"
            )
        }
    }

    /// KUU-3898: annotation classes must declare `val` parameters and value
    /// classes require one, so kotlinc exempts them from the
    /// property-parameter rule.
    @Test func testExpectAnnotationAndValueClassKeepPropertyParameters() throws {
        try withTemporaryFile(
            contents: """
            expect annotation class A(val x: Int)
            expect value class V(val x: Int)
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                !errors.contains { $0.code == "KSWIFTK-SEMA-0456" },
                "Annotation and value expect classes keep their `val` parameters: \(errors)"
            )
        }
    }

    /// KUU-3898: non-expect enums keep their entry bodies and constructor
    /// calls — the shape rules only apply in expect context.
    @Test func testNonExpectEnumEntryBodiesStayLegal() throws {
        try withTemporaryFile(
            contents: """
            enum class E(val v: Int) {
                A(1) { val x: Int = 1 },
                B(2)
            }
            """
        ) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["common-module"],
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                !errors.contains {
                    $0.code == "KSWIFTK-SEMA-0457"
                        || $0.code == "KSWIFTK-SEMA-0458"
                        || $0.code == "KSWIFTK-SEMA-0459"
                },
                "Non-expect enum entries keep bodies and constructor calls: \(errors)"
            )
        }
    }

    private func makeImportedExpectLibrary(indexed: Bool) throws -> URL {
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
        let encoder = MetadataEncoder()
        let metadata = indexed ? encoder.serializeIndexed([record]) : encoder.serialize([record])
        try manifest.write(to: libraryDirectory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libraryDirectory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        return libraryDirectory
    }
}
#endif
