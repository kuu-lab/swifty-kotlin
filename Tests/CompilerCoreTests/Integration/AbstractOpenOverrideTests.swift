#if canImport(Testing)
import Testing
@testable import CompilerCore

@Suite struct AbstractOpenOverrideTests {

    // MARK: - Original Test Case Validation

    @Test func testOriginalAbstractOpenOverrideCase() throws {
        let source = """
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
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // Should be valid - basic inheritance scenario
        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testMissingAbstractOverride() throws {
        let source = """
        abstract class Shape {
            abstract fun area(): Double
            open fun describe(): String = "I am a shape"
        }
        class Circle(val r: Double) : Shape() {
            // Missing override for abstract area()
            override fun describe(): String = "Circle"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // Should error - missing abstract override
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testMissingOverrideModifier() throws {
        let source = """
        abstract class Shape {
            abstract fun area(): Double
            open fun describe(): String = "I am a shape"
        }
        class Circle(val r: Double) : Shape() {
            override fun area(): Double = 3.14159 * r * r
            fun describe(): String = "Circle" // Missing override modifier
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // Should error - missing override modifier
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: ctx)
    }

    // MARK: - Advanced Test Cases

    @Test func testAbstractOverrideChaining() throws {
        let source = """
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
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // Should be valid - abstract override chaining
        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testFinalOverrideTermination() throws {
        let source = """
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
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // Should error - cannot override final
        assertHasDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
    }

}
#endif
