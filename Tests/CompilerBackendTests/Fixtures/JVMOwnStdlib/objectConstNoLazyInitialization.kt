// Reading a `const val` of an object / companion is inlined at the use site
// and must not run the owner's lazy initializer; a non-const member access
// still must.
object O {
    const val C = 1
    val d = 2
    init { println("O init") }
    fun f() = "O.f"
}

class K {
    companion object {
        const val X = 5
        const val S = "s"
        val y = 6
        init { println("K init") }
    }
}

object P {
    const val Q = 7
    init { println("P init") }
    fun g() = "P.g"
}

fun main() {
    println(O.C)
    println(K.X)
    println(K.S)
    println(P.Q)
    println("before non-const")
    println(O.d)
    println(O.C)
    println(K.y)
    println(P.g())
    println("end")
}
