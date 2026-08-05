#if canImport(Testing)
import Testing
@testable import CompilerCore

@Suite struct AbstractOpenOverrideTests {

    @Test func testAbstractOpenOverrideCases() throws {
        let sources: [String] = [
            // testOriginalAbstractOpenOverrideCase
            """
            package sample0

                    abstract class Shape {
                        abstract fun area(): Double
                        open fun describe(): String = "I am a shape"
                    }
                    class Circle(val r: Double) : Shape() {
                        override fun area(): Double = 3.14159 * r * r
                        override fun describe(): String = "Circle"
                    }
                    class Rect(val w: Double, val h: Double) : Shape() {
                        override fun area(): Double = w * h
                    }
                    fun main() {
                        val c = Circle(5.0)
                        println(c.describe())
                        println(c.area())
                        val r = Rect(3.0, 4.0)
                        println(r.describe())
                        println(r.area())
                    }
            """,
            // testMissingAbstractOverride
            """
            package sample1

                    abstract class Shape {
                        abstract fun area(): Double
                        open fun describe(): String = "I am a shape"
                    }
                    class Circle(val r: Double) : Shape() {
                        // Missing override for abstract area()
                        override fun describe(): String = "Circle"
                    }
            """,
            // testMissingOverrideModifier
            """
            package sample2

                    abstract class Shape {
                        abstract fun area(): Double
                        open fun describe(): String = "I am a shape"
                    }
                    class Circle(val r: Double) : Shape() {
                        override fun area(): Double = 3.14159 * r * r
                        fun describe(): String = "Circle" // Missing override modifier
                    }
            """,
            // testAbstractOverrideChaining
            """
            package sample3

                    abstract class Shape {
                        abstract fun area(): Double
                        open fun describe(): String = "Shape"
                    }

                    abstract class RegularShape : Shape() {
                        abstract override fun area(): Double
                        override fun describe(): String = "Regular Shape"
                    }

                    class Circle(val r: Double) : RegularShape() {
                        override fun area(): Double = 3.14159 * r * r
                        final override fun describe(): String = "Circle"
                    }
            """,
            // testFinalOverrideTermination
            """
            package sample4

                    open class Shape {
                        open fun describe(): String = "Shape"
                    }

                    class Circle : Shape() {
                        final override fun describe(): String = "Circle"
                    }

                    // This should error - cannot override final
                    class ColoredCircle : Circle() {
                        override fun describe(): String = "Colored Circle"
                    }
            """,
            // testPrimaryConstructorOverridePropertiesImplementInterface
            """
            package sample5

                    interface CommandProcessor {
                        val pluginId: String
                        val displayName: String
                    }

                    class MyCommandProcessor(
                        override val pluginId: String,
                        override val displayName: String
                    ) : CommandProcessor

                    fun main() {
                        val p = MyCommandProcessor("id", "name")
                        println(p.pluginId)
                    }
            """,
            // testPrimaryConstructorOverrideVarPropertyImplementsAbstractClassMember
            """
            package sample6

                    abstract class Container {
                        abstract var items: List<String>
                    }

                    class Box(override var items: List<String>) : Container()
            """,
            // testMixedPrimaryConstructorAndBodyOverrideProperties
            """
            package sample7

                    interface CommandProcessor {
                        val pluginId: String
                        val displayName: String
                    }

                    class MyCommandProcessor(
                        override val pluginId: String
                    ) : CommandProcessor {
                        override val displayName: String = "static-name"
                    }
            """,
            // testMissingPrimaryConstructorOverrideStillReportsAbstractMember
            """
            package sample8

                    interface CommandProcessor {
                        val pluginId: String
                        val displayName: String
                    }

                    class MyCommandProcessor(
                        val pluginId: String
                    ) : CommandProcessor
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testOriginalAbstractOpenOverrideCase
            do {
                let diags = diagnosticsForPath(paths[0], in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: diags)
                assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: diags)
                assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diags)
                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: diags)
                assertNoDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: diags)
                #expect(!(diags.contains(where: { $0.severity == .error })))
            }

            // testMissingAbstractOverride
            do {
                assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: diagnosticsForPath(paths[1], in: ctx))
            }

            // testMissingOverrideModifier
            do {
                assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnosticsForPath(paths[2], in: ctx))
            }

            // testAbstractOverrideChaining
            do {
                let diags = diagnosticsForPath(paths[3], in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: diags)
                #expect(!(diags.contains(where: { $0.severity == .error })))
            }

            // testFinalOverrideTermination
            do {
                assertHasDiagnostic("KSWIFTK-SEMA-FINAL", in: diagnosticsForPath(paths[4], in: ctx))
            }

            // testPrimaryConstructorOverridePropertiesImplementInterface
            do {
                let diags = diagnosticsForPath(paths[5], in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: diags)
                #expect(!(diags.contains(where: { $0.severity == .error })))
            }

            // testPrimaryConstructorOverrideVarPropertyImplementsAbstractClassMember
            do {
                let diags = diagnosticsForPath(paths[6], in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: diags)
                #expect(!(diags.contains(where: { $0.severity == .error })))
            }

            // testMixedPrimaryConstructorAndBodyOverrideProperties
            do {
                let diags = diagnosticsForPath(paths[7], in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: diags)
                #expect(!(diags.contains(where: { $0.severity == .error })))
            }

            // testMissingPrimaryConstructorOverrideStillReportsAbstractMember
            do {
                assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: diagnosticsForPath(paths[8], in: ctx))
            }
        }
    }

}
#endif
