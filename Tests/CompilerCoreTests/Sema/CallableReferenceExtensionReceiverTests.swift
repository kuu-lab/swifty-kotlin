#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-961: A bare `::name` callable reference must not resolve to an
/// extension function or extension property — kotlinc reports
/// `unresolved reference` for `::ext` where `ext` is `fun Int.ext()`.
/// Extensions are only reachable through `Type::ext`, `obj::ext`, or the
/// implicitly-bound `::ext` form inside a receiver scope. Member
/// functions that are also extensions (`fun Int.ext()` inside a class)
/// are unreferenceable in every `::` form ("member and an extension at
/// the same time" is prohibited).
@Suite
struct CallableReferenceExtensionReceiverTests {

    // MARK: - Bare `::` must reject extension declarations

    @Test func testBareCallableRefRejectsExtensionFunction() throws {
        let source = """
        fun Int.even(): Boolean = this % 2 == 0

        fun main() {
            val f = ::even
            println(f)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "Bare `::even` to a package-level extension must be rejected like kotlinc"
        )
    }

    @Test func testBareCallableRefRejectsExtensionProperty() throws {
        let source = """
        val Int.lastDigit: Int get() = this % 10

        fun main() {
            val p = ::lastDigit
            println(p)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "Bare `::lastDigit` to a package-level extension property must be rejected"
        )
    }

    @Test func testBareCallableRefRejectsExtensionInsideClass() throws {
        let source = """
        fun Int.even(): Boolean = this % 2 == 0

        class Probe {
            fun capture() = ::even
        }

        fun main() { println(Probe().capture()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "Bare `::even` stays rejected inside an unrelated class scope"
        )
    }

    @Test func testBareCallableRefRejectsLocalExtension() throws {
        let source = """
        fun main() {
            fun Int.local(): Int = this * 2
            val f = ::local
            println(f)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "Bare `::local` to a local extension must be rejected"
        )
    }

    // MARK: - Member-extensions are unreferenceable in every `::` form

    @Test func testMemberExtensionRejectedViaThis() throws {
        let source = """
        class C {
            fun Int.ext(): Int = 1
            fun capture() = this::ext
        }

        fun main() { println(C().capture()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "`this::ext` member-extension reference must be rejected")
    }

    @Test func testMemberExtensionRejectedViaType() throws {
        let source = """
        class C {
            fun Int.ext(): Int = 1
            fun capture() = C::ext
        }

        fun main() { println(C().capture()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "`C::ext` member-extension reference must be rejected")
    }

    @Test func testMemberExtensionRejectedViaInstance() throws {
        let source = """
        class C {
            fun Int.ext(): Int = 1
        }

        fun capture(c: C) = c::ext

        fun main() { println(capture(C())) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "`c::ext` member-extension reference must be rejected")
    }

    @Test func testMemberExtensionRejectedBareInsideOwner() throws {
        let source = """
        class C {
            fun Int.ext(): Int = 1
            fun capture() = ::ext
        }

        fun main() { println(C().capture()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Bare `::ext` inside the declaring class must be rejected")
    }

    @Test func testMemberExtensionPropertyRejected() throws {
        let source = """
        class C {
            val Int.mp: Int get() = 2
            fun capture() = this::mp
        }

        fun main() { println(C().capture()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Member-extension property `this::mp` must be rejected")
    }

    @Test func testImplicitBoundRefRejectsMismatchedExtensionReceiver() throws {
        let source = """
        fun String.tag(): String = "ext:" + this

        fun main() {
            val f = with(4) { ::tag }
            println(f)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "`::tag` inside `with(4)` must reject a String extension (receiver mismatch)"
        )
    }

    // MARK: - Legal forms must keep working

    @Test func testTypeQualifiedExtensionFunctionReference() throws {
        let source = """
        fun Int.even(): Boolean = this % 2 == 0

        fun main() {
            val f: (Int) -> Boolean = Int::even
            println(f(6))
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "`Int::even` unbound extension reference must type-check, got: \(errors)")
    }

    @Test func testBoundExtensionFunctionReference() throws {
        let source = """
        fun Int.even(): Boolean = this % 2 == 0

        fun main() {
            val f: () -> Boolean = 6::even
            println(f())
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "`6::even` bound extension reference must type-check, got: \(errors)")
    }

    @Test func testExtensionPropertyViaTypeAndInstance() throws {
        let source = """
        val Int.lastDigit: Int get() = this % 10

        fun main() {
            val unbound = Int::lastDigit
            val bound = 37::lastDigit
            println(unbound.get(37))
            println(bound.get())
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Extension property refs via `Int::`/`i::` must type-check, got: \(errors)")
    }

    @Test func testImplicitReceiverBoundExtensionReference() throws {
        let source = """
        fun Int.even(): Boolean = this % 2 == 0

        fun main() {
            // A bare `::ext` inside a receiver scope is a bound reference
            // (`this::ext`): kotlinc types it `() -> Boolean`.
            val f: () -> Boolean = with(4) { ::even }
            println(f())
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "`with(4) { ::even }` must bind the extension to the implicit receiver as `() -> Boolean`, got: \(errors)"
        )
    }

    @Test func testImplicitBoundExtensionInsideExtensionBody() throws {
        let source = """
        fun Int.odd(): Boolean = this % 2 == 1
        fun Int.evenProbe(): () -> Boolean = ::odd

        fun main() { println(4.evenProbe()()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "`::odd` inside an Int extension body binds to the extension receiver, got: \(errors)"
        )
    }

    @Test func testBoundMemberReferenceInsideClassStillWorks() throws {
        let source = """
        class C {
            fun m(): Int = 1
            fun capture() = ::m
        }

        fun main() { println(C().capture()()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Bound `::m` member reference must keep working, got: \(errors)")
    }

    @Test(arguments: [
        "with(\"s\") { with(1) { ::tag } }",
        "with(\"s\") { with(1) { with(true) { ::tag } } }",
        "with(\"outer\") { with(\"inner\") { ::tag } }",
    ])
    func testImplicitExtensionCallableRefSearchesReceiverStack(expression: String) throws {
        let ctx = makeContextFromSource("""
        fun String.tag(): String = "ext:" + this
        fun main() {
            val f: () -> String = \(expression)
            println(f())
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Implicit reference must bind the matching receiver: \(errors)")
    }

    @Test(arguments: [
        "with(37) { ::lastDigit }",
        "with(37) { with(\"s\") { ::lastDigit } }",
    ])
    func testImplicitExtensionPropertyCallableRefIsBound(expression: String) throws {
        let ctx = makeContextFromSource("""
        val Int.lastDigit: Int get() = this % 10
        fun main() {
            val p: kotlin.reflect.KProperty0<Int> = \(expression)
            println(p.get())
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Implicit extension property must be a bound KProperty0: \(errors)")
    }

    @Test(arguments: [
        "fun Int.ext(): Int = 1",
        "val Int.ext: Int get() = 1",
    ])
    func testMemberExtensionRejectedInNestedReceiverScope(declaration: String) throws {
        let ctx = makeContextFromSource("""
        class C {
            \(declaration)
            fun capture() = with(1) { ::ext }
        }
        fun main() { println(C().capture()) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Member extensions must remain unreferenceable")
    }

    @Test func testCallableReferenceDoesNotBindDslHiddenReceiver() throws {
        let ctx = makeContextFromSource("""
        @DslMarker annotation class Marker
        @Marker class Outer
        @Marker class Inner
        fun Outer.tag(): String = "outer"
        fun main() {
            val f = with(Outer()) { with(Inner()) { ::tag } }
            println(f)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "A shared DSL marker hides the outer implicit receiver")
    }

    @Test func testBareCallableRefToTopLevelFunctionStillWorks() throws {
        let source = """
        fun double(x: Int): Int = x * 2

        fun main() {
            val f = ::double
            println(f(5))
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Bare `::double` to a top-level function must keep working, got: \(errors)")
    }
}
#endif
