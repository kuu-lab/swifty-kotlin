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

    @Test func testExtensionFunctionShorthandCallsSema() throws {
        let sources: [String] = [
            // testCompanionExtensionFunctionShorthandCall
            """
            package sample0
                    class MyClass {
                        companion object
                    }

                    fun MyClass.Companion.extensionFun(): String = "extended"

                    fun main() {
                        val result: String = MyClass.extensionFun()
                    }

            """,

            // testCompanionExtensionFunctionWithArgumentShorthandCall
            """
            package sample1
                    class Widget {
                        companion object
                    }

                    fun Widget.Companion.create(count: Int): Widget = Widget()

                    fun main() {
                        val w: Widget = Widget.create(3)
                    }

            """,

            // testCompanionExtensionPropertyShorthandCall
            """
            package sample2
                    class Data {
                        companion object
                    }

                    val Data.Companion.extensionProp: Int get() = 42

                    fun main() {
                        val value: Int = Data.extensionProp
                    }

            """,

            // testNamedCompanionExtensionFunctionShorthandCall
            """
            package sample3
                    class Service {
                        companion object Factory
                    }

                    fun Service.Factory.create(): Service = Service()

                    fun main() {
                        val s: Service = Service.create()
                    }

            """,

            // testInterfaceCompanionExtensionFunctionShorthandCall
            """
            package sample4
                    interface ClockLike {
                        companion object
                    }

                    fun ClockLike.Companion.system(): Int = 42

                    fun main() {
                        val result: Int = ClockLike.system()
                    }

            """,

            // testExtensionFunctionOnBundledInstantCompanionShorthandCall
            """
            package sample5
                    import kotlin.time.Instant

                    fun Instant.Companion.epoch(): Instant = Instant.fromEpochMilliseconds(0L)

                    fun main() {
                        val i: Instant = Instant.epoch()
                    }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testCompanionExtensionFunctionShorthandCall

            do {
                let sample0Path = paths[0]
                let sampleDiags = diagnosticsForPath(sample0Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for companion extension function shorthand call, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testCompanionExtensionFunctionWithArgumentShorthandCall

            do {
                let sample1Path = paths[1]
                let sampleDiags = diagnosticsForPath(sample1Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for companion extension function (with argument) shorthand call, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testCompanionExtensionPropertyShorthandCall

            do {
                let sample2Path = paths[2]
                let sampleDiags = diagnosticsForPath(sample2Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for companion extension property shorthand call, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testNamedCompanionExtensionFunctionShorthandCall

            do {
                let sample3Path = paths[3]
                let sampleDiags = diagnosticsForPath(sample3Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for named companion extension function shorthand call, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testInterfaceCompanionExtensionFunctionShorthandCall

            do {
                let sample4Path = paths[4]
                let sampleDiags = diagnosticsForPath(sample4Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for interface companion extension function shorthand call, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testExtensionFunctionOnBundledInstantCompanionShorthandCall

            do {
                let sample5Path = paths[5]
                let sampleDiags = diagnosticsForPath(sample5Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for extension function on bundled Instant.Companion, got: \(sampleDiags.map(\.code))"
                        )

            }

        }
    }



    /// Mirrors the exact KSP-472 blocker scenario: a Kotlin-source extension
    /// function declared on the bundled `kotlin.time.Instant` class's
    /// synthetic `Companion` (registered in
    /// `HeaderHelpers+SyntheticInstantStubs.swift`), invoked with the
    /// shorthand call form. This is the concrete proof that KSP-CAP-003's
    /// fix unblocks KSP-472's `kk_instant_now`/`kk_clock_system_now` wiring.



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
