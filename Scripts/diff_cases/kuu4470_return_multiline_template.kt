fun t(b: Boolean): String {
    return "ab'${
        if (b) { "x" } else { "y" }
    }'"
}

fun unbracedElse(b: Boolean): String {
    return "pre${
        if (b) "x"
        else "y"
    }post"
}

fun unbracedBranch(b: Boolean): String {
    if (b) return "u${
        1 + 2
    }" else return "none"
}

fun whenEntry(b: Boolean): String {
    return when (b) {
        true -> "w${
            5
        }"
        else -> "z"
    }
}

fun whenCondition(b: Boolean): String {
    val s = if (b) "ax" else "zz"
    return when (s) {
        "a${
            if (b) "x" else "y"
        }" -> "match"
        else -> "nomatch"
    }
}

fun nested(b: Boolean): String {
    return "n${
        "inner${
            if (b) 1 else 2
        }"
    }"
}

fun infixInTemplate(): String {
    return "i${
        1
            .plus(2)
    }"
}

fun main() {
    println(t(true))
    println(t(false))
    println(unbracedElse(true))
    println(unbracedElse(false))
    println(unbracedBranch(true))
    println(unbracedBranch(false))
    println(whenEntry(true))
    println(whenEntry(false))
    println(whenCondition(true))
    println(whenCondition(false))
    println(nested(true))
    println(nested(false))
    println(infixInTemplate())
}
