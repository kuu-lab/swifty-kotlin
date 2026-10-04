package golden.sema

fun mapMinBy(map: Map<String, Int>) = map.minBy { it.value }

fun mapMinOfComparable(map: Map<String, Int>): String = map.minOf { it.key }

fun mapMinOfDouble(map: Map<String, Int>): Double = map.minOf { it.value.toDouble() }

fun mapMinOfFloat(map: Map<String, Int>): Float = map.minOf { it.value.toFloat() }

fun mapMinOfOrNullComparable(map: Map<String, Int>): String? = map.minOfOrNull { it.key }

fun mapMinOfOrNullDouble(map: Map<String, Int>): Double? = map.minOfOrNull { it.value.toDouble() }

fun mapMinOfOrNullFloat(map: Map<String, Int>): Float? = map.minOfOrNull { it.value.toFloat() }

fun mapMinOfWith(map: Map<String, Int>): Int =
    map.minOfWith(naturalOrder<Int>()) { it.value }

fun mapMinOfWithOrNull(map: Map<String, Int>): Int? =
    map.minOfWithOrNull(naturalOrder<Int>()) { it.value }

fun mapMinWith(map: Map<String, Int>) =
    map.minWith(compareBy { it.value })

fun mapMinWithOrNull(map: Map<String, Int>) =
    map.minWithOrNull(compareBy { it.value })
