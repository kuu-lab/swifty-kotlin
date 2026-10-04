fun describe(level: DeprecationLevel): String = when (level) {
    DeprecationLevel.WARNING -> "warning"
    DeprecationLevel.ERROR -> "error"
    DeprecationLevel.HIDDEN -> "hidden"
}

fun main() {
    println(describe(DeprecationLevel.WARNING))
    println(describe(DeprecationLevel.ERROR))
    println(describe(DeprecationLevel.HIDDEN))
}
