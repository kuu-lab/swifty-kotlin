package kotlin.ranges

public infix fun Int.until(to: Int): IntRange =
    if (to == Int.MIN_VALUE) IntRange(1, 0) else IntRange(this, to - 1)

public inline fun IntRange.all(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (!predicate(element)) return false
    return true
}
