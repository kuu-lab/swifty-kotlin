package kotlin.collections

// KSP-687: primitive array higher-order functions are bundled Kotlin source.
// The generated-looking repetition mirrors Kotlin's specialized primitive-array API.
// It keeps element values typed at the source boundary instead of passing raw words
// through the former kk_array_* runtime HOF bridges.

// --- UIntArray ---

public fun UIntArray.elementAt(index: Int): UInt = this[index]

public fun UIntArray.getOrNull(index: Int): UInt? =
    if (index >= 0 && index < size) this[index] else null

public inline fun UIntArray.elementAtOrElse(index: Int, defaultValue: (Int) -> UInt): UInt =
    if (index >= 0 && index < size) this[index] else defaultValue(index)

public fun UIntArray.indexOf(element: UInt): Int {
    var i = 0
    while (i < this.size) {
        if (this[i] == element) return i
        i++
    }
    return -1
}

public inline fun UIntArray.indexOfFirst(predicate: (UInt) -> Boolean): Int {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return i
        i++
    }
    return -1
}

public inline fun UIntArray.indexOfLast(predicate: (UInt) -> Boolean): Int {
    var i = this.size - 1
    while (i >= 0) {
        if (predicate(this[i])) return i
        i--
    }
    return -1
}

public inline fun UIntArray.forEachIndexed(action: (Int, UInt) -> Unit) {
    var i = 0
    while (i < this.size) {
        action(i, this[i])
        i++
    }
}

public fun UIntArray.maxOrNull(): UInt? {
    if (this.size == 0) return null
    var max = this[0]
    var i = 1
    while (i < this.size) {
        val element = this[i]
        if (element > max) max = element
        i++
    }
    return max
}

public fun UIntArray.minOrNull(): UInt? {
    if (this.size == 0) return null
    var min = this[0]
    var i = 1
    while (i < this.size) {
        val element = this[i]
        if (element < min) min = element
        i++
    }
    return min
}

public fun <R> UIntArray.map(transform: (UInt) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <R> UIntArray.mapIndexed(transform: (Int, UInt) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <R : Any> UIntArray.mapNotNull(transform: (UInt) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <R> UIntArray.flatMap(transform: (UInt) -> List<R>): List<R> {
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

public fun UIntArray.forEach(action: (UInt) -> Unit) {
    var i = 0
    while (i < this.size) {
        action(this[i])
        i++
    }
}

public fun UIntArray.filter(predicate: (UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun UIntArray.filterIndexed(predicate: (Int, UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public fun UIntArray.filterNot(predicate: (UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun UIntArray.reduce(operation: (UInt, UInt) -> UInt): UInt {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun UIntArray.reduceIndexed(operation: (Int, UInt, UInt) -> UInt): UInt {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun UIntArray.reduceOrNull(operation: (UInt, UInt) -> UInt): UInt? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> UIntArray.fold(initial: R, operation: (R, UInt) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> UIntArray.foldIndexed(initial: R, operation: (Int, R, UInt) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun UIntArray.find(predicate: (UInt) -> Boolean): UInt? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun UIntArray.findLast(predicate: (UInt) -> Boolean): UInt? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun UIntArray.first(): UInt {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[0]
}

public fun UIntArray.first(predicate: (UInt) -> Boolean): UInt {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun UIntArray.firstOrNull(): UInt? {
    if (this.size == 0) return null
    return this[0]
}

public fun UIntArray.firstOrNull(predicate: (UInt) -> Boolean): UInt? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun UIntArray.last(): UInt {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[this.size - 1]
}

public fun UIntArray.last(predicate: (UInt) -> Boolean): UInt {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun UIntArray.lastOrNull(): UInt? {
    if (this.size == 0) return null
    return this[this.size - 1]
}

public fun UIntArray.lastOrNull(predicate: (UInt) -> Boolean): UInt? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun UIntArray.single(): UInt {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    if (this.size != 1) throw IllegalArgumentException("Array has more than one element.")
    return this[0]
}

public fun UIntArray.singleOrNull(): UInt? = if (this.size == 1) this[0] else null

public inline fun UIntArray.single(predicate: (UInt) -> Boolean): UInt {
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

public inline fun UIntArray.singleOrNull(predicate: (UInt) -> Boolean): UInt? {
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

public fun UIntArray.any(): Boolean = this.size != 0

public fun UIntArray.any(predicate: (UInt) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun UIntArray.all(predicate: (UInt) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun UIntArray.none(): Boolean = this.size == 0

public fun UIntArray.none(predicate: (UInt) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun UIntArray.count(): Int = this.size

public fun UIntArray.count(predicate: (UInt) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}

public fun UIntArray.joinToString(separator: String = ", ", prefix: String = "", postfix: String = ""): String {
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

public fun UIntArray.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (UInt) -> String
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

// --- ULongArray ---

public fun ULongArray.elementAt(index: Int): ULong = this[index]

public fun ULongArray.getOrNull(index: Int): ULong? =
    if (index >= 0 && index < size) this[index] else null

public inline fun ULongArray.elementAtOrElse(index: Int, defaultValue: (Int) -> ULong): ULong =
    if (index >= 0 && index < size) this[index] else defaultValue(index)

public inline fun ULongArray.indexOfFirst(predicate: (ULong) -> Boolean): Int {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return i
        i++
    }
    return -1
}

public inline fun ULongArray.indexOfLast(predicate: (ULong) -> Boolean): Int {
    var i = this.size - 1
    while (i >= 0) {
        if (predicate(this[i])) return i
        i--
    }
    return -1
}

public fun <R> ULongArray.map(transform: (ULong) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <R> ULongArray.mapIndexed(transform: (Int, ULong) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <R : Any> ULongArray.mapNotNull(transform: (ULong) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <R> ULongArray.flatMap(transform: (ULong) -> List<R>): List<R> {
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

public fun ULongArray.forEach(action: (ULong) -> Unit) {
    var i = 0
    while (i < this.size) {
        action(this[i])
        i++
    }
}

public fun ULongArray.filter(predicate: (ULong) -> Boolean): List<ULong> {
    val result = mutableListOf<ULong>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun ULongArray.filterIndexed(predicate: (Int, ULong) -> Boolean): List<ULong> {
    val result = mutableListOf<ULong>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public fun ULongArray.filterNot(predicate: (ULong) -> Boolean): List<ULong> {
    val result = mutableListOf<ULong>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun ULongArray.reduce(operation: (ULong, ULong) -> ULong): ULong {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun ULongArray.reduceIndexed(operation: (Int, ULong, ULong) -> ULong): ULong {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun ULongArray.reduceOrNull(operation: (ULong, ULong) -> ULong): ULong? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> ULongArray.fold(initial: R, operation: (R, ULong) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> ULongArray.foldIndexed(initial: R, operation: (Int, R, ULong) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun ULongArray.find(predicate: (ULong) -> Boolean): ULong? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun ULongArray.findLast(predicate: (ULong) -> Boolean): ULong? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun ULongArray.first(): ULong {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[0]
}

public fun ULongArray.first(predicate: (ULong) -> Boolean): ULong {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun ULongArray.firstOrNull(): ULong? {
    if (this.size == 0) return null
    return this[0]
}

public fun ULongArray.firstOrNull(predicate: (ULong) -> Boolean): ULong? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun ULongArray.last(): ULong {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[this.size - 1]
}

public fun ULongArray.last(predicate: (ULong) -> Boolean): ULong {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun ULongArray.lastOrNull(): ULong? {
    if (this.size == 0) return null
    return this[this.size - 1]
}

public fun ULongArray.lastOrNull(predicate: (ULong) -> Boolean): ULong? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun ULongArray.single(): ULong {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    if (this.size != 1) throw IllegalArgumentException("Array has more than one element.")
    return this[0]
}

public fun ULongArray.singleOrNull(): ULong? = if (this.size == 1) this[0] else null

public inline fun ULongArray.single(predicate: (ULong) -> Boolean): ULong {
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

public inline fun ULongArray.singleOrNull(predicate: (ULong) -> Boolean): ULong? {
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

public fun ULongArray.any(): Boolean = this.size != 0

public fun ULongArray.any(predicate: (ULong) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun ULongArray.all(predicate: (ULong) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun ULongArray.none(): Boolean = this.size == 0

public fun ULongArray.none(predicate: (ULong) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun ULongArray.count(): Int = this.size

public fun ULongArray.count(predicate: (ULong) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}

public fun ULongArray.joinToString(separator: String = ", ", prefix: String = "", postfix: String = ""): String {
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

public fun ULongArray.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (ULong) -> String
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
