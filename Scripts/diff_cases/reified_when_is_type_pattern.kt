inline fun <reified T> inspect(x: Any?): String = when (x) {
    is T -> "yes"
    else -> "no"
}

inline fun <reified T> inspectNegated(x: Any?): String = when (x) {
    !is T -> "other"
    else -> "match"
}

fun main() {
    println(inspect<String>("x"))
    println(inspect<Int>("x"))
    println(inspect<List<*>>(listOf(1)))
    println(inspect<String?>(null))
    println(inspectNegated<String>("x"))
    println(inspectNegated<Int>("x"))
}
