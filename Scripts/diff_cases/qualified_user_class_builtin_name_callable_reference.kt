// KUU-4163: user-defined classifiers whose names collide with primitive or
// builtin type names must keep their own identity in qualified type
// positions and callable references. `foo.Int`, `Outer.Int`, and bare `Int`
// inside package foo all denote the user class, not kotlin.Int; only
// `kotlin.Int` itself resolves to the primitive.
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
    fun marker(): kotlin.Int = 4
}

class Outer {
    class Int {
        fun bar(x: Int): Int = x
    }
}

fun takesQualified(x: foo.Int): foo.Int = x

fun box(): kotlin.String {
    val a: foo.Int = foo.Int()
    val b: foo.Int = foo.Int()
    // Qualified expected type + qualified callable reference receiver.
    val g: (foo.Int, foo.Int) -> foo.Int = foo.Int::bar
    if (g(a, b) !== b) return "Fail foo.Int::bar"
    if (takesQualified(a) !== a) return "Fail foo.Int signature"
    // Unqualified names in the same package still denote the user class,
    // including members named like primitive operators.
    val h: (Int, Int) -> Int = Int::bar
    if (h(a, b) !== b) return "Fail Int::bar"
    val hu: (Int, Int) -> Int = Int::plus
    if (hu(a, b) !== b) return "Fail Int::plus"
    val i: Int = a
    if (i !== a) return "Fail Int type"
    val sr: (String) -> String = String::self
    val s: String = foo.String()
    if (sr(s) !== s) return "Fail String::self"
    if (s.marker() != 4) return "Fail String member"
    // Nested classifier whose name collides with a builtin.
    val na = Outer.Int()
    val nb = Outer.Int()
    val n: (Outer.Int, Outer.Int) -> Outer.Int = Outer.Int::bar
    if (n(na, nb) !== nb) return "Fail Outer.Int::bar"
    val nf: (foo.Outer.Int, foo.Outer.Int) -> foo.Outer.Int = foo.Outer.Int::bar
    if (nf(na, nb) !== nb) return "Fail foo.Outer.Int::bar"
    // Non-colliding control cases keep working.
    val m: (MyInt, MyInt) -> MyInt = MyInt::bar
    val ma = MyInt()
    val mb = MyInt()
    if (m(ma, mb) !== mb) return "Fail MyInt::bar"
    // A user member named like a primitive operator stays a user member.
    val p: (foo.Int, foo.Int) -> foo.Int = foo.Int::plus
    if (p(a, b) !== b) return "Fail foo.Int::plus"
    // kotlin.-qualified builtins still denote the primitives.
    val k: kotlin.Int = 40 + 2
    if (k != 42) return "Fail kotlin.Int"
    return "OK"
}

fun main() {
    println(box())
}
