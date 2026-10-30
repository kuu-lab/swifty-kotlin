fun classify(x: Any): String {
    return when (x) {
        is String if x.length > 3 -> "long string"
        is Int
            if x > 0 -> "positive"
        else if x is Boolean -> "guarded else"
        else
            if x is Double -> "split else"
        else -> "other"
    }
}

fun assigned(x: Any): String {
    val result = when (x) {
        1 if x == 1 -> "one"
        else -> "other"
    }
    return result
}
