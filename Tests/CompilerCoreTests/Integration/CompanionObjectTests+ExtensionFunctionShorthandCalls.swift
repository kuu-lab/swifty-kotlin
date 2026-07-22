#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - KSP-CAP-003: Companion-receiver extension function shorthand calls

/// `CompanionObjectTests+PrivateAccess.swift` only exercises the fully
/// qualified call form (`MyClass.Companion.extensionFun()`), which resolves
/// through plain member access on `Companion` and never reaches the
/// class-name-receiver companion fallback in
/// `CallTypeChecker+MemberCallInferenceRegularResolution.swift`. These tests
/// pin the shorthand form (`MyClass.extensionFun()`, no `.Companion.`) that
/// KSP-CAP-003 is specifically about.
extension CompanionObjectTests {
    @Test func testCompanionExtensionFunctionShorthandCall() throws {
        let source = """
        class MyClass {
            companion object
        }

        fun MyClass.Companion.extensionFun(): String = "extended"

        fun main() {
            val result: String = MyClass.extensionFun()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no sema errors for companion extension function shorthand call, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    @Test func testCompanionExtensionFunctionWithArgumentShorthandCall() throws {
        let source = """
        class Widget {
            companion object
        }

        fun Widget.Companion.create(count: Int): Widget = Widget()

        fun main() {
            val w: Widget = Widget.create(3)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no sema errors for companion extension function (with argument) shorthand call, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    @Test func testCompanionExtensionPropertyShorthandCall() throws {
        let source = """
        class Data {
            companion object
        }

        val Data.Companion.extensionProp: Int get() = 42

        fun main() {
            val value: Int = Data.extensionProp
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no sema errors for companion extension property shorthand call, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    @Test func testNamedCompanionExtensionFunctionShorthandCall() throws {
        let source = """
        class Service {
            companion object Factory
        }

        fun Service.Factory.create(): Service = Service()

        fun main() {
            val s: Service = Service.create()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no sema errors for named companion extension function shorthand call, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    @Test func testInterfaceCompanionExtensionFunctionShorthandCall() throws {
        let source = """
        interface ClockLike {
            companion object
        }

        fun ClockLike.Companion.system(): Int = 42

        fun main() {
            val result: Int = ClockLike.system()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no sema errors for interface companion extension function shorthand call, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Mirrors the exact KSP-472 blocker scenario: a Kotlin-source extension
    /// function declared on the bundled `kotlin.time.Instant` class's
    /// synthetic `Companion` (registered in
    /// `HeaderHelpers+SyntheticInstantStubs.swift`), invoked with the
    /// shorthand call form. This is the concrete proof that KSP-CAP-003's
    /// fix unblocks KSP-472's `kk_instant_now`/`kk_clock_system_now` wiring.
    @Test func testExtensionFunctionOnBundledInstantCompanionShorthandCall() throws {
        let source = """
        import kotlin.time.Instant

        fun Instant.Companion.epoch(): Instant = Instant.fromEpochMilliseconds(0L)

        fun main() {
            val i: Instant = Instant.epoch()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no sema errors for extension function on bundled Instant.Companion, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    @Test func testCompanionExtensionFunctionShorthandCallKIRLowering() throws {
        let source = """
        class MyClass {
            companion object
        }

        fun MyClass.Companion.extensionFun(): String = "extended"

        fun main() {
            val result: String = MyClass.extensionFun()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no KIR errors for companion extension function shorthand call, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )

        let module = try #require(ctx.kir)
        let functionNames = findAllKIRFunctions(in: module).map { function in
            ctx.interner.resolve(function.name)
        }
        #expect(
            functionNames.contains("extensionFun"),
            "Expected companion extension function in KIR, got: \(functionNames)"
        )
    }
}
#endif
