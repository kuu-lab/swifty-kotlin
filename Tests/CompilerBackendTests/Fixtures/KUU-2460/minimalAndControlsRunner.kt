import kuu2460.minimal.box as minimalBox

fun explicitParameterControl(): String {
    val f: Function1<Any?, *> = { value: Any? -> value }
    return f("OK") as String
}

fun concreteReturnControl(): String {
    val f: Function1<Any?, Any?> = { "OK" }
    return f("OK") as String
}

fun function0StarReturnControl(): String {
    val f: Function0<*> = { "OK" }
    return f() as String
}

fun function2StarReturnControl(): String {
    val f: Function2<Any?, Int, *> = { value, suffix -> value.toString() + suffix.toString() }
    return f("O", 75) as String
}

fun main() {
    if (box() != "OK") return
    if (minimalBox() != "OK") return
    if (explicitParameterControl() != "OK") return
    if (concreteReturnControl() != "OK") return
    if (function0StarReturnControl() != "OK") return
    if (function2StarReturnControl() != "O75") return
    println("OK")
}
