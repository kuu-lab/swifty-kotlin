fun classify(x: Any?): String = when (x) {
    is String -> "string:$x"
    in listOf(1, 2, 3) -> "small"
    !in listOf(4, 5, 6) -> "big-ish"
    4 -> "four"
    else -> "other"
}
