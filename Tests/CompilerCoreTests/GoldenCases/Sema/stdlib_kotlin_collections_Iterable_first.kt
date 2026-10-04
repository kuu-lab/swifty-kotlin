fun firstValue(values: Iterable<Int>): Int = values.first()

fun firstMatching(values: Iterable<Int>): Int = values.first { it > 1 }

fun firstNotNullValue(values: Iterable<Int>): String =
    values.firstNotNullOf { if (it > 1) "hit" else null }

fun firstNotNullValueOrNull(values: Iterable<Int>): String? =
    values.firstNotNullOfOrNull { if (it > 1) "hit" else null }

fun firstValueOrNull(values: Iterable<Int>): Int? = values.firstOrNull()

fun firstMatchingOrNull(values: Iterable<Int>): Int? = values.firstOrNull { it > 1 }
