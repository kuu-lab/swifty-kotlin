// KUU-2945: `O.P` uses `O` as a pure namespace qualifier -- the enclosing
// object's initializer must not run when a delegated property (or a direct
// member path) reaches the nested singleton `P`. `P`'s own initializer still
// runs exactly once.
// JetBrains: delegatedProperty/delegateToSingleton/noInitializationOfOuterClass.kt

object O {
    object P {
        init { println("P init") }
        val tag = "P"
    }
    init { println("O init") }
}

operator fun O.P.getValue(thisRef: Any?, property: Any?): String = "OK"

val result by O.P

fun main() {
    println(result)
    println(O.P.tag)
}
