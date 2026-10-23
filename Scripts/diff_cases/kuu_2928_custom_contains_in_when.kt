operator fun Int.contains(value: Int): Boolean = this == 2 && value == 1

fun matchIn(): String = when (1) {
    in 2 -> "in"
    else -> "fail"
}

fun matchNotIn(): String = when (1) {
    !in 3 -> "not in"
    else -> "fail"
}

fun main() {
    println(matchIn())
    println(matchNotIn())
}
