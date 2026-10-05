#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache

/// Regression tests for four Sema typing gaps found together:
/// enum `Comparable` bounds, common-supertype LUB, range literals as
/// `Iterable` arguments, and companion objects used as their interface type.
@Suite
struct EnumLubRangeCompanionTypingTests {
    private func semaErrors(_ source: String, allowDefaultStdlibLibrary: Bool = false) throws -> [String] {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSource(source, emit: .executable, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        if allowDefaultStdlibLibrary { #expect(ctx.options.stdlibLibraryPath != nil) }
        try runSema(ctx)
        return ctx.diagnostics.diagnostics
            .filter { $0.severity == .error }
            .map { "\($0.code): \($0.message)" }
    }

    @Test(arguments: [false, true])
    func userEnumSatisfiesComparableUpperBound(allowDefaultStdlibLibrary: Bool) throws {
        let errors = try semaErrors("""
        enum class Color { RED, GREEN, BLUE }
        fun <T : Comparable<T>> biggest(a: T, b: T): T = if (a > b) a else b
        fun probe() {
            println(listOf(Color.BLUE, Color.RED).sorted())
            println(listOf(Color.BLUE, Color.RED).sortedDescending())
            println(listOf(Color.BLUE, Color.RED).maxOrNull())
            println(maxOf(Color.RED, Color.BLUE))
            println(biggest(Color.RED, Color.BLUE))
        }
        """, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test
    func lubOfSiblingsKeepsCommonInterfaceAndSuperclass() throws {
        let errors = try semaErrors("""
        interface I { fun a(): String; val p: Int }
        class X : I { override fun a() = "xa"; override val p = 1 }
        class Y : I { override fun a() = "ya"; override val p = 2 }
        open class Base { open fun n() = "base" }
        class C1 : Base() { override fun n() = "c1" }
        class C2 : Base() { override fun n() = "c2" }
        fun probe(flag: Boolean) {
            val ws = listOf(X(), Y())
            println(ws.map { it.a() })
            println(ws.map { it.p })
            println(listOf(C1(), C2()).map { it.n() })
            val pick = if (flag) X() else Y()
            println(pick.a())
        }
        """)
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test
    func lubDoesNotPickGenericSupertypeWhenTypeArgumentsDisagree() throws {
        // Box<Int> and Box<String> share only `Any`; choosing `Box<Int>` for both would be unsound,
        // so `get()` must not resolve on the element type.
        let errors = try semaErrors("""
        interface Box<T> { fun get(): T }
        class IntBox : Box<Int> { override fun get() = 1 }
        class StrBox : Box<String> { override fun get() = "s" }
        fun probe() {
            val xs = listOf(IntBox(), StrBox())
            println(xs[0].get())
        }
        """)
        #expect(!errors.isEmpty)
    }

    @Test
    func rangeLiteralIsAcceptedAsIterableArgument() throws {
        let errors = try semaErrors("""
        fun count(x: Iterable<Int>) = x.count()
        fun sumAll(xs: Iterable<Int>): Int { var s = 0; for (x in xs) s += x; return s }
        fun probe() {
            println(count(1..3))
            println(count(1 until 3))
            println(count(3 downTo 1))
            println(count(1..10 step 3))
            println(sumAll(1..4))
        }
        """)
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test
    func rangeLiteralStillRejectedForMismatchedIterableElementType() throws {
        let errors = try semaErrors("""
        fun count(x: Iterable<String>) = x.count()
        fun probe() { println(count(1..3)) }
        """)
        #expect(!errors.isEmpty)
    }

    @Test
    func companionObjectIsUsableAsItsInterfaceSupertype() throws {
        let errors = try semaErrors("""
        interface Factory<T> { fun create(): T }
        class Widget(val id: Int) {
            companion object : Factory<Widget> { override fun create() = Widget(0) }
        }
        fun <T> makeTwo(f: Factory<T>): List<T> = listOf(f.create(), f.create())
        fun probe() {
            println(makeTwo(Widget))
            val f: Factory<Widget> = Widget
            val g: Factory<Widget> = Widget.Companion
            val h = Widget
            println(f.create().id + g.create().id + h.create().id)
        }
        """)
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test
    func companionObjectWithoutSupertypeIsNotAnInterfaceValue() throws {
        let errors = try semaErrors("""
        interface Factory { fun create(): String }
        class Widget { companion object { fun create() = "x" } }
        fun probe() { val f: Factory = Widget }
        """)
        #expect(!errors.isEmpty)
    }
}
#endif
