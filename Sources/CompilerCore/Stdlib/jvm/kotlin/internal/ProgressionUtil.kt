package kotlin.internal

// a mod b (in arithmetical sense)
private fun progressionMod(a: Int, b: Int): Int {
    val mod = a % b
    return if (mod >= 0) mod else mod + b
}

// (a - b) mod c
private fun progressionDifferenceModulo(a: Int, b: Int, c: Int): Int =
    progressionMod(progressionMod(a, c) - progressionMod(b, c), c)

public fun getProgressionLastElement(start: Int, end: Int, step: Int): Int = when {
    step > 0 -> if (start >= end) end else end - progressionDifferenceModulo(end, start, step)
    step < 0 -> if (start <= end) end else end + progressionDifferenceModulo(start, end, -step)
    else -> throw IllegalArgumentException("Step is zero.")
}

// a mod b (in arithmetical sense)
private fun progressionMod(a: Long, b: Long): Long {
    val mod = a % b
    return if (mod >= 0) mod else mod + b
}

// (a - b) mod c
private fun progressionDifferenceModulo(a: Long, b: Long, c: Long): Long =
    progressionMod(progressionMod(a, c) - progressionMod(b, c), c)

public fun getProgressionLastElement(start: Long, end: Long, step: Long): Long = when {
    step > 0 -> if (start >= end) end else end - progressionDifferenceModulo(end, start, step)
    step < 0 -> if (start <= end) end else end + progressionDifferenceModulo(start, end, -step)
    else -> throw IllegalArgumentException("Step is zero.")
}
