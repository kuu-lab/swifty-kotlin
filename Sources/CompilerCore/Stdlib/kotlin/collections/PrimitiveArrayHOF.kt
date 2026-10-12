package kotlin.collections

// KSP-687: primitive array higher-order functions are bundled Kotlin source.
// The generated-looking repetition mirrors Kotlin's specialized primitive-array API.
// It keeps element values typed at the source boundary instead of passing raw words
// through the former kk_array_* runtime HOF bridges.

// --- IntArray ---

public fun <R> IntArray.map(transform: (Int) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(this[i]))
        i++
    }
    return result
}
public fun <R> IntArray.mapIndexed(transform: (Int, Int) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <R : Any> IntArray.mapNotNull(transform: (Int) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <R> IntArray.flatMap(transform: (Int) -> List<R>): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val nested = transform(this[i])
        var j = 0
        while (j < nested.size) {
            result.add(nested[j])
            j++
        }
        i++
    }
    return result
}

public inline fun IntArray.forEach(action: (Int) -> Unit) {
    var i = 0
    while (i < this.size) {
        action(this[i])
        i++
    }
}

public fun IntArray.filter(predicate: (Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun IntArray.filterIndexed(predicate: (Int, Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public fun IntArray.filterNot(predicate: (Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun IntArray.reduce(operation: (Int, Int) -> Int): Int {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun IntArray.reduceIndexed(operation: (Int, Int, Int) -> Int): Int {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun IntArray.reduceOrNull(operation: (Int, Int) -> Int): Int? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> IntArray.fold(initial: R, operation: (R, Int) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> IntArray.foldIndexed(initial: R, operation: (Int, R, Int) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun IntArray.find(predicate: (Int) -> Boolean): Int? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun IntArray.findLast(predicate: (Int) -> Boolean): Int? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun IntArray.first(): Int {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[0]
}

public fun IntArray.first(predicate: (Int) -> Boolean): Int {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun IntArray.firstOrNull(): Int? {
    if (this.size == 0) return null
    return this[0]
}

public fun IntArray.firstOrNull(predicate: (Int) -> Boolean): Int? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun IntArray.last(): Int {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[this.size - 1]
}

public fun IntArray.last(predicate: (Int) -> Boolean): Int {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun IntArray.lastOrNull(): Int? {
    if (this.size == 0) return null
    return this[this.size - 1]
}

public fun IntArray.lastOrNull(predicate: (Int) -> Boolean): Int? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun IntArray.single(): Int {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    if (this.size != 1) throw IllegalArgumentException("Array has more than one element.")
    return this[0]
}

public fun IntArray.singleOrNull(): Int? = if (this.size == 1) this[0] else null

public inline fun IntArray.single(predicate: (Int) -> Boolean): Int {
    var matchIndex = -1
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) throw IllegalArgumentException("Array contains more than one matching element.")
            matchIndex = i
        }
        i++
    }
    if (matchIndex >= 0) return this[matchIndex]
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public inline fun IntArray.singleOrNull(predicate: (Int) -> Boolean): Int? {
    var matchIndex = -1
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) return null
            matchIndex = i
        }
        i++
    }
    return if (matchIndex >= 0) this[matchIndex] else null
}

public fun IntArray.any(): Boolean = this.size != 0

public fun IntArray.any(predicate: (Int) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun IntArray.all(predicate: (Int) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun IntArray.none(): Boolean = this.size == 0

public fun IntArray.none(predicate: (Int) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun IntArray.count(): Int = this.size

public fun IntArray.count(predicate: (Int) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}

public fun IntArray.joinToString(separator: String = ", ", prefix: String = "", postfix: String = ""): String {
    val sb = StringBuilder()
    sb.append(prefix)
    var i = 0
    while (i < this.size) {
        if (i > 0) sb.append(separator)
        sb.append(this[i].toString())
        i++
    }
    sb.append(postfix)
    return sb.toString()
}

public fun IntArray.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (Int) -> String
): String {
    val sb = StringBuilder()
    sb.append(prefix)
    var i = 0
    while (i < this.size) {
        if (i > 0) sb.append(separator)
        sb.append(transform(this[i]))
        i++
    }
    sb.append(postfix)
    return sb.toString()
}

// --- LongArray ---

public fun <R> LongArray.map(transform: (Long) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <R> LongArray.mapIndexed(transform: (Int, Long) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <R : Any> LongArray.mapNotNull(transform: (Long) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <R> LongArray.flatMap(transform: (Long) -> List<R>): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val nested = transform(this[i])
        var j = 0
        while (j < nested.size) {
            result.add(nested[j])
            j++
        }
        i++
    }
    return result
}

public fun LongArray.forEach(action: (Long) -> Unit) {
    var i = 0
    while (i < this.size) {
        action(this[i])
        i++
    }
}

public fun LongArray.filter(predicate: (Long) -> Boolean): List<Long> {
    val result = mutableListOf<Long>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun LongArray.filterIndexed(predicate: (Int, Long) -> Boolean): List<Long> {
    val result = mutableListOf<Long>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public fun LongArray.filterNot(predicate: (Long) -> Boolean): List<Long> {
    val result = mutableListOf<Long>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun LongArray.reduce(operation: (Long, Long) -> Long): Long {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun LongArray.reduceIndexed(operation: (Int, Long, Long) -> Long): Long {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun LongArray.reduceOrNull(operation: (Long, Long) -> Long): Long? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> LongArray.fold(initial: R, operation: (R, Long) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> LongArray.foldIndexed(initial: R, operation: (Int, R, Long) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun LongArray.find(predicate: (Long) -> Boolean): Long? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun LongArray.findLast(predicate: (Long) -> Boolean): Long? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun LongArray.first(): Long {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[0]
}

public fun LongArray.first(predicate: (Long) -> Boolean): Long {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun LongArray.firstOrNull(): Long? {
    if (this.size == 0) return null
    return this[0]
}

public fun LongArray.firstOrNull(predicate: (Long) -> Boolean): Long? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun LongArray.last(): Long {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[this.size - 1]
}

public fun LongArray.last(predicate: (Long) -> Boolean): Long {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun LongArray.lastOrNull(): Long? {
    if (this.size == 0) return null
    return this[this.size - 1]
}

public fun LongArray.lastOrNull(predicate: (Long) -> Boolean): Long? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun LongArray.single(): Long {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    if (this.size != 1) throw IllegalArgumentException("Array has more than one element.")
    return this[0]
}

public fun LongArray.singleOrNull(): Long? = if (this.size == 1) this[0] else null

public inline fun LongArray.single(predicate: (Long) -> Boolean): Long {
    var matchIndex = -1
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) throw IllegalArgumentException("Array contains more than one matching element.")
            matchIndex = i
        }
        i++
    }
    if (matchIndex >= 0) return this[matchIndex]
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public inline fun LongArray.singleOrNull(predicate: (Long) -> Boolean): Long? {
    var matchIndex = -1
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) return null
            matchIndex = i
        }
        i++
    }
    return if (matchIndex >= 0) this[matchIndex] else null
}

public fun LongArray.any(): Boolean = this.size != 0

public fun LongArray.any(predicate: (Long) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun LongArray.all(predicate: (Long) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun LongArray.none(): Boolean = this.size == 0

public fun LongArray.none(predicate: (Long) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun LongArray.count(): Int = this.size

public fun LongArray.count(predicate: (Long) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}

public fun LongArray.joinToString(separator: String = ", ", prefix: String = "", postfix: String = ""): String {
    val sb = StringBuilder()
    sb.append(prefix)
    var i = 0
    while (i < this.size) {
        if (i > 0) sb.append(separator)
        sb.append(this[i].toString())
        i++
    }
    sb.append(postfix)
    return sb.toString()
}

public fun LongArray.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (Long) -> String
): String {
    val sb = StringBuilder()
    sb.append(prefix)
    var i = 0
    while (i < this.size) {
        if (i > 0) sb.append(separator)
        sb.append(transform(this[i]))
        i++
    }
    sb.append(postfix)
    return sb.toString()
}
