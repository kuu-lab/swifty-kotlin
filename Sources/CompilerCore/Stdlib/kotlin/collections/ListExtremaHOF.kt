package kotlin.collections

public inline fun <T : Comparable<T>> List<T>.max(): T {
    if (size == 0) throw NoSuchElementException("List is empty.")
    var best = this[0]
    var i = 1
    while (i < size) {
        if (best < this[i]) best = this[i]
        i++
    }
    return best
}

public inline fun <T : Comparable<T>> List<T>.maxOrNull(): T? {
    if (size == 0) return null
    var best = this[0]
    var i = 1
    while (i < size) {
        if (best < this[i]) best = this[i]
        i++
    }
    return best
}

public inline fun <T : Comparable<T>> List<T>.min(): T {
    if (size == 0) throw NoSuchElementException("List is empty.")
    var best = this[0]
    var i = 1
    while (i < size) {
        if (best > this[i]) best = this[i]
        i++
    }
    return best
}

public inline fun <T : Comparable<T>> List<T>.minOrNull(): T? {
    if (size == 0) return null
    var best = this[0]
    var i = 1
    while (i < size) {
        if (best > this[i]) best = this[i]
        i++
    }
    return best
}

public inline fun <T, R : Comparable<R>> List<T>.maxBy(selector: (T) -> R): T {
    if (size == 0) throw NoSuchElementException("List is empty.")
    var bestElem = this[0]
    var bestKey = selector(bestElem)
    var i = 1
    while (i < size) {
        val elem = this[i]
        val key = selector(elem)
        if (bestKey < key) { bestElem = elem; bestKey = key }
        i++
    }
    return bestElem
}

public inline fun <T, R : Comparable<R>> List<T>.maxByOrNull(selector: (T) -> R): T? {
    if (size == 0) return null
    var bestElem = this[0]
    var bestKey = selector(bestElem)
    var i = 1
    while (i < size) {
        val elem = this[i]
        val key = selector(elem)
        if (bestKey < key) { bestElem = elem; bestKey = key }
        i++
    }
    return bestElem
}

public inline fun <T, R : Comparable<R>> List<T>.minBy(selector: (T) -> R): T {
    if (size == 0) throw NoSuchElementException("List is empty.")
    var bestElem = this[0]
    var bestKey = selector(bestElem)
    var i = 1
    while (i < size) {
        val elem = this[i]
        val key = selector(elem)
        if (bestKey > key) { bestElem = elem; bestKey = key }
        i++
    }
    return bestElem
}

public inline fun <T, R : Comparable<R>> List<T>.minByOrNull(selector: (T) -> R): T? {
    if (size == 0) return null
    var bestElem = this[0]
    var bestKey = selector(bestElem)
    var i = 1
    while (i < size) {
        val elem = this[i]
        val key = selector(elem)
        if (bestKey > key) { bestElem = elem; bestKey = key }
        i++
    }
    return bestElem
}

public inline fun <T, R : Comparable<R>> List<T>.maxOf(selector: (T) -> R): R {
    if (size == 0) throw NoSuchElementException("List is empty.")
    var bestKey = selector(this[0])
    var i = 1
    while (i < size) {
        val key = selector(this[i])
        if (bestKey < key) bestKey = key
        i++
    }
    return bestKey
}

public inline fun <T, R : Comparable<R>> List<T>.maxOfOrNull(selector: (T) -> R): R? {
    if (size == 0) return null
    var bestKey = selector(this[0])
    var i = 1
    while (i < size) {
        val key = selector(this[i])
        if (bestKey < key) bestKey = key
        i++
    }
    return bestKey
}

public inline fun <T, R : Comparable<R>> List<T>.minOf(selector: (T) -> R): R {
    if (size == 0) throw NoSuchElementException("List is empty.")
    var bestKey = selector(this[0])
    var i = 1
    while (i < size) {
        val key = selector(this[i])
        if (bestKey > key) bestKey = key
        i++
    }
    return bestKey
}

public inline fun <T, R : Comparable<R>> List<T>.minOfOrNull(selector: (T) -> R): R? {
    if (size == 0) return null
    var bestKey = selector(this[0])
    var i = 1
    while (i < size) {
        val key = selector(this[i])
        if (bestKey > key) bestKey = key
        i++
    }
    return bestKey
}

public inline fun <T> List<T>.maxWith(comparator: Comparator<in T>): T {
    if (size == 0) throw NoSuchElementException("List is empty.")
    var best = this[0]
    var i = 1
    while (i < size) {
        if (comparator.compare(best, this[i]) < 0) best = this[i]
        i++
    }
    return best
}

public inline fun <T> List<T>.maxWithOrNull(comparator: Comparator<in T>): T? {
    if (size == 0) return null
    var best = this[0]
    var i = 1
    while (i < size) {
        if (comparator.compare(best, this[i]) < 0) best = this[i]
        i++
    }
    return best
}

public inline fun <T> List<T>.minWith(comparator: Comparator<in T>): T {
    if (size == 0) throw NoSuchElementException("List is empty.")
    var best = this[0]
    var i = 1
    while (i < size) {
        if (comparator.compare(best, this[i]) > 0) best = this[i]
        i++
    }
    return best
}

public inline fun <T> List<T>.minWithOrNull(comparator: Comparator<in T>): T? {
    if (size == 0) return null
    var best = this[0]
    var i = 1
    while (i < size) {
        if (comparator.compare(best, this[i]) > 0) best = this[i]
        i++
    }
    return best
}

public inline fun <T, R> List<T>.maxOfWith(comparator: Comparator<R>, selector: (T) -> R): R {
    if (size == 0) throw NoSuchElementException("List is empty.")
    var bestValue = selector(this[0])
    var i = 1
    while (i < size) {
        val value = selector(this[i])
        if (comparator.compare(bestValue, value) < 0) bestValue = value
        i++
    }
    return bestValue
}

public inline fun <T, R> List<T>.maxOfWithOrNull(comparator: Comparator<R>, selector: (T) -> R): R? {
    if (size == 0) return null
    var bestValue = selector(this[0])
    var i = 1
    while (i < size) {
        val value = selector(this[i])
        if (comparator.compare(bestValue, value) < 0) bestValue = value
        i++
    }
    return bestValue
}

public inline fun <T, R> List<T>.minOfWith(comparator: Comparator<R>, selector: (T) -> R): R {
    if (size == 0) throw NoSuchElementException("List is empty.")
    var bestValue = selector(this[0])
    var i = 1
    while (i < size) {
        val value = selector(this[i])
        if (comparator.compare(bestValue, value) > 0) bestValue = value
        i++
    }
    return bestValue
}

public inline fun <T, R> List<T>.minOfWithOrNull(comparator: Comparator<R>, selector: (T) -> R): R? {
    if (size == 0) return null
    var bestValue = selector(this[0])
    var i = 1
    while (i < size) {
        val value = selector(this[i])
        if (comparator.compare(bestValue, value) > 0) bestValue = value
        i++
    }
    return bestValue
}
