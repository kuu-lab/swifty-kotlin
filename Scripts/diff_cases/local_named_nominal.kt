// KUU-555: named local `class` declarations inside function and lambda
// bodies must construct, resolve, and run like file-scope classes.

fun localClassCase(): Int {
    class Local(val v: Int)
    val l = Local(5)
    return l.v
}

open class Base(val v: Int)

fun localClassSuperCase(x: Int): Int {
    class Named : Base(x)
    return Named().v
}

class Outer {
    fun localClassInMethod(): Int {
        class Local(val v: Int)
        return Local(9).v
    }
}

fun lambdaCase(): Int {
    val f = {
        class C(val x: Int)
        C(4).x
    }
    return f()
}

fun captureCase(a: Int): Int {
    class C(val x: Int) {
        fun get() = x + a
    }
    return C(2).get()
}

fun main() {
    println(localClassCase())
    println(localClassSuperCase(7))
    println(Outer().localClassInMethod())
    println(lambdaCase())
    println(captureCase(5))
}
