// KUU-571: enum entries with anonymous class bodies must remain referencable
// and dispatch their overridden members through the enum-typed value.
enum class E(val w: Int) {
    X(1) {
        override fun f() = "x"
    },
    Y(2) {
        override fun f() = "y"
    };

    abstract fun f(): String
}

enum class Op {
    PLUS {
        override fun apply(a: Int, b: Int) = a + b
    },
    TIMES {
        override fun apply(a: Int, b: Int) = a * b
    };

    abstract fun apply(a: Int, b: Int): Int
}

fun main() {
    println(E.X.f())
    println(E.Y.w)
    println(E.X.name)
    println(E.entries)
    println(Op.PLUS.apply(2, 3))
    println(Op.TIMES.apply(2, 3))
    println(Op.valueOf("TIMES").apply(4, 5))
}
