#if canImport(Testing)
import Testing
@testable import CompilerCore
@testable import CompilerTestSupport

@Suite struct AbstractOpenOverrideTests {

    // MARK: - Shared Sema contexts

    private static let positiveSources: [String] = [
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
        """
        package sample1
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
        """
        package sample2
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
        """
        package sample3
        abstract class Container {
            abstract var items: List<String>
        }

        class Box(override var items: List<String>) : Container()
        """,
        """
        package sample4
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
    ]

    private static let negativeSources: [String] = [
        """
        package sample5
        abstract class Shape {
            abstract fun area(): Double
            open fun describe(): String = "I am a shape"
        }
        class Circle(val r: Double) : Shape() {
            // Missing override for abstract area()
            override fun describe(): String = "Circle"
        }
        """,
        """
        package sample6
        abstract class Shape {
            abstract fun area(): Double
            open fun describe(): String = "I am a shape"
        }
        class Circle(val r: Double) : Shape() {
            override fun area(): Double = 3.14159 * r * r
            fun describe(): String = "Circle" // Missing override modifier
        }
        """,
        """
        package sample7
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

    private static let _positiveCtx = Result {
        try semaContext(for: positiveSources)
    }

    private static let _negativeCtx = Result {
        try semaContext(for: negativeSources)
    }

    private func positiveCtx() throws -> CompilationContext {
        try Self._positiveCtx.get()
    }

    private func negativeCtx() throws -> CompilationContext {
        try Self._negativeCtx.get()
    }

    // MARK: - Original Test Case Validation

    @Test func testOriginalAbstractOpenOverrideCase() throws {
        let ctx = try positiveCtx()

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test func testMissingAbstractOverride() throws {
        let ctx = try negativeCtx()

        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testMissingOverrideModifier() throws {
        let ctx = try negativeCtx()

        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: ctx)
    }

    // MARK: - Advanced Test Cases

    @Test func testFinalOverrideTermination() throws {
        let ctx = try negativeCtx()

        assertHasDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
    }

    // MARK: - Primary constructor `override val` / `override var` properties

    @Test func testPrimaryConstructorOpenPropertyCanBeOverridden() throws {
        let source = """
        open class Base(open val p: String)

        class Derived(p: String) : Base(p) {
            override val p: String = p + "!"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test func testExpectMembersWithoutBodiesAreContracts() throws {
        let source = """
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
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError)
    }

    @Test func testSealedClassesWithoutAbstractMembersDoNotWarn() throws {
        let source = """
        sealed class Grammar
        class A : Grammar()

        sealed class PartData {
            fun dispose() {}
        }

        abstract sealed class ExplicitAbstract

        sealed class Container {
            sealed class NestedSealed
            abstract class NestedAbstract
        }

        sealed interface SealedInterface
        abstract class RegularEmpty
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError)
        let emptyAbstractWarnings = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-ABSTRACT"
                && $0.severity == .warning
                && $0.message.contains("has no abstract members")
        }
        #expect(emptyAbstractWarnings.isEmpty)
    }

    @Test func testEmptyExpectAbstractClassDoesNotWarn() throws {
        let source = """
        expect abstract class CharsetEncoder

        actual abstract class CharsetEncoder {
            abstract fun encode(): String
        }

        abstract class RegularEmpty
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let emptyAbstractWarnings = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-ABSTRACT"
                && $0.message.contains("has no abstract members")
        }
        #expect(emptyAbstractWarnings.isEmpty)
        #expect(!ctx.diagnostics.hasError)
    }

    // MARK: - Enum entry overrides of final kotlin.Enum members (KUU-3748)

    @Test func testEnumEntryCannotOverrideFinalNameProperty() throws {
        let source = """
        enum class H {
            FIRST { override val name get() = "first!" },
            SECOND
        }
        fun main() {
            println(H.FIRST.name)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
    }

    @Test func testEnumEntryCannotOverrideFinalOrdinalProperty() throws {
        let source = """
        enum class H {
            FIRST { override val ordinal get() = 99 },
            SECOND
        }
        fun main() {
            println(H.FIRST.ordinal)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
    }

    @Test func testEnumEntryCannotOverrideFinalNameThroughInterface() throws {
        // kotlinc reports 'name' in 'H' is final even though the same-named
        // interface property would otherwise be a valid override target.
        let source = """
        interface Named { val name: String }
        enum class H : Named {
            FIRST { override val name get() = "first!" },
            SECOND
        }
        fun main() {
            val h: Named = H.FIRST
            println(h.name)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
    }

    @Test func testEnumEntryCannotOverrideFinalInheritedFunction() throws {
        let source = """
        enum class H {
            FIRST { override fun hashCode() = 1 },
            SECOND
        }
        fun main() {
            println(H.FIRST.hashCode())
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
    }

    @Test func testEnumEntryCanOverrideAbstractAndOpenMembers() throws {
        let source = """
        enum class H {
            FIRST { override val label get() = "f"; override fun describe() = "first"; override fun toString() = "FIRST!" },
            SECOND { override val label get() = "s"; override fun describe() = "second" };
            abstract val label: String
            abstract fun describe(): String
        }
        fun main() {
            println(H.FIRST.label)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test func testEnumEntryCanOverrideInterfaceProperty() throws {
        let source = """
        interface Labelled { val label: String }
        enum class H : Labelled {
            FIRST { override val label get() = "first" },
            SECOND { override val label get() = "second" }
        }
        fun main() {
            println(H.FIRST.label)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    // MARK: - Property/function override namespaces (KUU-4106)

    // kotlinc keeps `val p` and `fun p()` in separate override namespaces.
    // A same-named final function must not make an abstract property look
    // final, and a same-named open function must not make a final property
    // look overridable.

    @Test func testAbstractPropertyOverridableDespiteSameNamedFunction() throws {
        // sqldelight `Transacter.Transaction` shape: a `protected abstract val`
        // next to an internal same-named helper function.
        let source = """
        interface Transacter {
            abstract class Transaction {
                private val ownerThreadId = 0
                protected abstract val enclosingTransaction: Transaction?
                internal fun enclosingTransaction() = enclosingTransaction
            }
        }
        class Driver : Transacter {
            private inner class Transaction(
                override val enclosingTransaction: Transacter.Transaction?,
            ) : Transacter.Transaction()
        }
        fun main() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test func testAbstractValAndVarOverridableDespiteSameNamedFunctions() throws {
        let source = """
        abstract class Base {
            protected abstract val p: Base?
            internal fun p() = p
            protected abstract var q: Base?
            internal fun q() = q
        }
        class Derived : Base() {
            override val p: Base? = null
            override var q: Base? = null
        }
        fun main() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test func testOpenPropertyOverridableDespiteSameNamedFunction() throws {
        let source = """
        abstract class Base {
            protected open val u: Base? = null
            internal fun u() = u
        }
        class Derived : Base() {
            override val u: Base? = null
        }
        fun main() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test func testEnumEntryOverridesAbstractPropertyDespiteSameNamedFunction() throws {
        let source = """
        enum class G {
            A { override val p: Int = 1 };
            abstract val p: Int
            fun p(): Int = 0
        }
        fun main() { println(G.A.p) }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test func testPropertyOverrideNothingWhenOnlyFunctionExists() throws {
        // kotlinc: 'p' overrides nothing (a val cannot override fun p()).
        let source = """
        abstract class Base {
            fun p(): Int = 0
        }
        class Derived : Base() {
            override val p: Int = 0
        }
        fun main() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-NOTHING", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
    }

    @Test func testFinalPropertyStillRejectsOverrideDespiteSameNamedOpenFunction() throws {
        // The open function must not mask the final property: kotlinc reports
        // 'r' in 'Base' is final and cannot be overridden.
        let source = """
        abstract class Base {
            val r: Int = 0
            open fun r(): Int = 0
        }
        class Derived : Base() {
            override val r: Int = 1
        }
        fun main() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
    }

    @Test func testFinalFunctionStillRejectsOverrideDespiteSameNamedAbstractProperty() throws {
        let source = """
        abstract class Base {
            abstract val s: Int
            fun s(): Int = s
        }
        class Derived : Base() {
            override val s: Int = 0
            override fun s(): Int = 1
        }
        fun main() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
    }

    @Test func testFunctionOverrideDoesNotImplementAbstractProperty() throws {
        // kotlinc: class 'Derived' is not abstract and does not implement
        // abstract base class member 'val p: Int'.
        let source = """
        abstract class Base {
            abstract val p: Int
            open fun p(): Int = 0
        }
        class Derived : Base() {
            override fun p(): Int = 1
        }
        fun main() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testPropertyOverrideDoesNotImplementAbstractFunction() throws {
        let source = """
        abstract class Base {
            abstract fun p(): Int
            open val p: Int = 0
        }
        class Derived : Base() {
            override val p: Int = 1
        }
        fun main() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

}
#endif
