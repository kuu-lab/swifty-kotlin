// KUU-555: named local `class`/`object` declarations inside function and
// lambda bodies must construct, resolve, and run like file-scope nominals.

fun localClassCase(): Int {
    class Local(val v: Int)
    val l = Local(5)
    return l.v
}

fun localObjectCase(): Int {
    object Local {
        val v = 5
    }
    return Local.v
}

open class Base(val v: Int)

fun localObjectSuperCase(x: Int): Int {
    object Named : Base(x)
    return Named.v
}

class Outer {
    fun localObjectInMethod(): Int {
        object Local {
            val v = 9
        }
        return Local.v
    }
}

fun lambdaCase(): Int {
    val f = {
        object L {
            val v = 3
        }
        class C(val x: Int)
        L.v + C(4).x
    }
    return f()
}

fun captureCase(a: Int): Int {
    object L {
        val v = a + 1
    }
    class C(val x: Int) {
        fun get() = x + a
    }
    return L.v + C(2).get()
}

fun main() {
    println(localClassCase())
    println(localObjectCase())
    println(localObjectSuperCase(7))
    println(Outer().localObjectInMethod())
    println(lambdaCase())
    println(captureCase(5))
}
