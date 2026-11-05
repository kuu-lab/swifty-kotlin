#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-4163: user-defined classifiers whose names collide with primitive or
/// builtin type names must keep their own identity in qualified type
/// positions and callable references. `foo.Int`, `Outer.Int`, and bare `Int`
/// inside package foo all denote the user class, not kotlin.Int; only
/// `kotlin.Int` itself resolves to the primitive.
@Suite
struct CallableReferenceBuiltinNameCollisionTests {

    private static let decls = """
    package foo

    class Int {
        fun bar(x: Int): Int = x
        fun plus(other: Int): Int = bar(other)
        fun self(): Int = this
    }

    class MyInt {
        fun bar(x: MyInt): MyInt = x
    }

    class String {
        fun self(): String = this
    }

    class Outer {
        class Int {
            fun bar(x: Int): Int = x
        }
    }

    fun takesQualified(x: foo.Int): foo.Int = x
    """

    private func semaErrors(_ source: String) throws -> [Diagnostic] {
        var result: [Diagnostic] = []
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            result = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        }
        return result
    }

    @Test
    func qualifiedTypePositionsResolveUserClassifier() throws {
        let errors = try semaErrors(Self.decls + """

        fun main() {
            val a: foo.Int = foo.Int()
            val f: (foo.Int) -> foo.Int = { it }
            val n: Outer.Int = Outer.Int()
            val nf: (foo.Outer.Int) -> foo.Outer.Int = { it }
            val s: String = foo.String()
            val c1 = takesQualified(a).self()
            val c2 = f(a).self()
            val c3 = nf(n).bar(n)
            val c4 = s.self()
        }
        """)
        #expect(errors.isEmpty, "Qualified builtin-colliding type names must resolve to the user classifier: \(errors)")
    }

    @Test
    func qualifiedCallableReferencesResolveUserClassifier() throws {
        let errors = try semaErrors(Self.decls + """

        fun main() {
            val a: foo.Int = foo.Int()
            val b: foo.Int = foo.Int()
            val g: (foo.Int, foo.Int) -> foo.Int = foo.Int::bar
            val p: (foo.Int, foo.Int) -> foo.Int = foo.Int::plus
            val na = Outer.Int()
            val nb = Outer.Int()
            val n: (Outer.Int, Outer.Int) -> Outer.Int = Outer.Int::bar
            val nf: (foo.Outer.Int, foo.Outer.Int) -> foo.Outer.Int = foo.Outer.Int::bar
            val m: (MyInt, MyInt) -> MyInt = MyInt::bar
            val ma = MyInt()
            val mb = MyInt()
            val c1 = g(a, b)
            val c2 = p(a, b)
            val c3 = n(na, nb)
            val c4 = nf(na, nb)
            val c5 = m(ma, mb)
        }
        """)
        #expect(errors.isEmpty, "Qualified callable references to builtin-colliding user classes must resolve: \(errors)")
    }

    @Test
    func unqualifiedCallableReferencesResolveUserClassifier() throws {
        let errors = try semaErrors(Self.decls + """

        fun main() {
            val a: foo.Int = foo.Int()
            val b: foo.Int = foo.Int()
            val g: (Int, Int) -> Int = Int::bar
            val up: (Int, Int) -> Int = Int::plus
            val sr: (String) -> String = String::self
            val s: String = foo.String()
            val c1 = g(a, b)
            val c2 = up(a, b)
            val c3 = sr(s)
        }
        """)
        #expect(errors.isEmpty, "Unqualified callable references to builtin-colliding user classes must resolve: \(errors)")
    }

    @Test
    func kotlinQualifiedAndBarePrimitiveReferencesKeepWorking() throws {
        // No user classifier shadows the builtin names in this source, so
        // `Int::plus` and `kotlin.Int::plus` both denote the primitive.
        let errors = try semaErrors("""
        fun main() {
            val qualified: (kotlin.Int, kotlin.Int) -> kotlin.Int = kotlin.Int::plus
            val bare: (Int, Int) -> Int = Int::plus
            val and: (Boolean, Boolean) -> Boolean = Boolean::and
            val k: kotlin.Int = 42
            val c1 = qualified(k, k)
            val c2 = bare(1, 2)
            val c3 = and(true, false)
        }
        """)
        #expect(errors.isEmpty, "kotlin.-qualified and bare primitive callable references must keep working: \(errors)")
    }

    @Test
    func missingMemberOnUserClassifierIsStillRejected() throws {
        let errors = try semaErrors(Self.decls + """

        fun main() {
            val bad: (foo.Int, foo.Int) -> foo.Int = foo.Int::compareTo
        }
        """)
        #expect(
            errors.contains { $0.code == "KSWIFTK-SEMA-0022" },
            "A member that does not exist on the user classifier must still be rejected: \(errors)"
        )
    }
}
#endif
