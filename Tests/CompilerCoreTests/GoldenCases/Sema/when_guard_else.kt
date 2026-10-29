fun classify(x: Any): String {
    return when (x) {
        is String if x.length > 3 -> "long string"
        else if x is Int -> "guarded else int"
        else -> "other"
    }
}
