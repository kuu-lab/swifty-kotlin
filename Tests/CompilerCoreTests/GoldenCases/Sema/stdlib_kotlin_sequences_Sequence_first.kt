fun firstNotNullValue(values: Sequence<Int>): String =
    values.firstNotNullOf { if (it > 1) "hit" else null }

fun firstNotNullValueOrNull(values: Sequence<Int>): String? =
    values.firstNotNullOfOrNull { if (it > 1) "hit" else null }
