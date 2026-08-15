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

public fun IntArray.forEach(action: (Int) -> Unit) {
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

// --- ByteArray ---

public fun <R> ByteArray.map(transform: (Byte) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <R> ByteArray.mapIndexed(transform: (Int, Byte) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <R : Any> ByteArray.mapNotNull(transform: (Byte) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <R> ByteArray.flatMap(transform: (Byte) -> List<R>): List<R> {
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

public fun ByteArray.forEach(action: (Byte) -> Unit) {
    var i = 0
    while (i < this.size) {
        action(this[i])
        i++
    }
}

public fun ByteArray.filter(predicate: (Byte) -> Boolean): List<Byte> {
    val result = mutableListOf<Byte>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun ByteArray.filterIndexed(predicate: (Int, Byte) -> Boolean): List<Byte> {
    val result = mutableListOf<Byte>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public fun ByteArray.filterNot(predicate: (Byte) -> Boolean): List<Byte> {
    val result = mutableListOf<Byte>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun ByteArray.reduce(operation: (Byte, Byte) -> Byte): Byte {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun ByteArray.reduceIndexed(operation: (Int, Byte, Byte) -> Byte): Byte {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun ByteArray.reduceOrNull(operation: (Byte, Byte) -> Byte): Byte? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> ByteArray.fold(initial: R, operation: (R, Byte) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> ByteArray.foldIndexed(initial: R, operation: (Int, R, Byte) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun ByteArray.find(predicate: (Byte) -> Boolean): Byte? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun ByteArray.findLast(predicate: (Byte) -> Boolean): Byte? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun ByteArray.first(): Byte {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[0]
}

public fun ByteArray.first(predicate: (Byte) -> Boolean): Byte {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun ByteArray.firstOrNull(): Byte? {
    if (this.size == 0) return null
    return this[0]
}

public fun ByteArray.firstOrNull(predicate: (Byte) -> Boolean): Byte? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun ByteArray.last(): Byte {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[this.size - 1]
}

public fun ByteArray.last(predicate: (Byte) -> Boolean): Byte {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun ByteArray.lastOrNull(): Byte? {
    if (this.size == 0) return null
    return this[this.size - 1]
}

public fun ByteArray.lastOrNull(predicate: (Byte) -> Boolean): Byte? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun ByteArray.any(): Boolean = this.size != 0

public fun ByteArray.any(predicate: (Byte) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun ByteArray.all(predicate: (Byte) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun ByteArray.none(): Boolean = this.size == 0

public fun ByteArray.none(predicate: (Byte) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun ByteArray.count(): Int = this.size

public fun ByteArray.count(predicate: (Byte) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}

public fun ByteArray.joinToString(separator: String = ", ", prefix: String = "", postfix: String = ""): String {
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

public fun ByteArray.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (Byte) -> String
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

// --- ShortArray ---

public fun <R> ShortArray.map(transform: (Short) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <R> ShortArray.mapIndexed(transform: (Int, Short) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <R : Any> ShortArray.mapNotNull(transform: (Short) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <R> ShortArray.flatMap(transform: (Short) -> List<R>): List<R> {
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

public fun ShortArray.forEach(action: (Short) -> Unit) {
    var i = 0
    while (i < this.size) {
        action(this[i])
        i++
    }
}

public fun ShortArray.filter(predicate: (Short) -> Boolean): List<Short> {
    val result = mutableListOf<Short>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun ShortArray.filterIndexed(predicate: (Int, Short) -> Boolean): List<Short> {
    val result = mutableListOf<Short>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public fun ShortArray.filterNot(predicate: (Short) -> Boolean): List<Short> {
    val result = mutableListOf<Short>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun ShortArray.reduce(operation: (Short, Short) -> Short): Short {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun ShortArray.reduceIndexed(operation: (Int, Short, Short) -> Short): Short {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun ShortArray.reduceOrNull(operation: (Short, Short) -> Short): Short? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> ShortArray.fold(initial: R, operation: (R, Short) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> ShortArray.foldIndexed(initial: R, operation: (Int, R, Short) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun ShortArray.find(predicate: (Short) -> Boolean): Short? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun ShortArray.findLast(predicate: (Short) -> Boolean): Short? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun ShortArray.first(): Short {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[0]
}

public fun ShortArray.first(predicate: (Short) -> Boolean): Short {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun ShortArray.firstOrNull(): Short? {
    if (this.size == 0) return null
    return this[0]
}

public fun ShortArray.firstOrNull(predicate: (Short) -> Boolean): Short? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun ShortArray.last(): Short {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[this.size - 1]
}

public fun ShortArray.last(predicate: (Short) -> Boolean): Short {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun ShortArray.lastOrNull(): Short? {
    if (this.size == 0) return null
    return this[this.size - 1]
}

public fun ShortArray.lastOrNull(predicate: (Short) -> Boolean): Short? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun ShortArray.any(): Boolean = this.size != 0

public fun ShortArray.any(predicate: (Short) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun ShortArray.all(predicate: (Short) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun ShortArray.none(): Boolean = this.size == 0

public fun ShortArray.none(predicate: (Short) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun ShortArray.count(): Int = this.size

public fun ShortArray.count(predicate: (Short) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}

public fun ShortArray.joinToString(separator: String = ", ", prefix: String = "", postfix: String = ""): String {
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

public fun ShortArray.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (Short) -> String
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

// --- UIntArray ---

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

// --- DoubleArray ---

public fun <R> DoubleArray.map(transform: (Double) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <R> DoubleArray.mapIndexed(transform: (Int, Double) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <R : Any> DoubleArray.mapNotNull(transform: (Double) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <R> DoubleArray.flatMap(transform: (Double) -> List<R>): List<R> {
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

public fun DoubleArray.forEach(action: (Double) -> Unit) {
    var i = 0
    while (i < this.size) {
        action(this[i])
        i++
    }
}

public fun DoubleArray.filter(predicate: (Double) -> Boolean): List<Double> {
    val result = mutableListOf<Double>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun DoubleArray.filterIndexed(predicate: (Int, Double) -> Boolean): List<Double> {
    val result = mutableListOf<Double>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public fun DoubleArray.filterNot(predicate: (Double) -> Boolean): List<Double> {
    val result = mutableListOf<Double>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun DoubleArray.reduce(operation: (Double, Double) -> Double): Double {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun DoubleArray.reduceIndexed(operation: (Int, Double, Double) -> Double): Double {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun DoubleArray.reduceOrNull(operation: (Double, Double) -> Double): Double? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> DoubleArray.fold(initial: R, operation: (R, Double) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> DoubleArray.foldIndexed(initial: R, operation: (Int, R, Double) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun DoubleArray.find(predicate: (Double) -> Boolean): Double? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun DoubleArray.findLast(predicate: (Double) -> Boolean): Double? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun DoubleArray.first(): Double {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[0]
}

public fun DoubleArray.first(predicate: (Double) -> Boolean): Double {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun DoubleArray.firstOrNull(): Double? {
    if (this.size == 0) return null
    return this[0]
}

public fun DoubleArray.firstOrNull(predicate: (Double) -> Boolean): Double? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun DoubleArray.last(): Double {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[this.size - 1]
}

public fun DoubleArray.last(predicate: (Double) -> Boolean): Double {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun DoubleArray.lastOrNull(): Double? {
    if (this.size == 0) return null
    return this[this.size - 1]
}

public fun DoubleArray.lastOrNull(predicate: (Double) -> Boolean): Double? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun DoubleArray.any(): Boolean = this.size != 0

public fun DoubleArray.any(predicate: (Double) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun DoubleArray.all(predicate: (Double) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun DoubleArray.none(): Boolean = this.size == 0

public fun DoubleArray.none(predicate: (Double) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun DoubleArray.count(): Int = this.size

public fun DoubleArray.count(predicate: (Double) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}

public fun DoubleArray.joinToString(separator: String = ", ", prefix: String = "", postfix: String = ""): String {
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

public fun DoubleArray.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (Double) -> String
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

// --- FloatArray ---

public fun <R> FloatArray.map(transform: (Float) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <R> FloatArray.mapIndexed(transform: (Int, Float) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <R : Any> FloatArray.mapNotNull(transform: (Float) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <R> FloatArray.flatMap(transform: (Float) -> List<R>): List<R> {
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

public fun FloatArray.forEach(action: (Float) -> Unit) {
    var i = 0
    while (i < this.size) {
        action(this[i])
        i++
    }
}

public fun FloatArray.filter(predicate: (Float) -> Boolean): List<Float> {
    val result = mutableListOf<Float>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun FloatArray.filterIndexed(predicate: (Int, Float) -> Boolean): List<Float> {
    val result = mutableListOf<Float>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public fun FloatArray.filterNot(predicate: (Float) -> Boolean): List<Float> {
    val result = mutableListOf<Float>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun FloatArray.reduce(operation: (Float, Float) -> Float): Float {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun FloatArray.reduceIndexed(operation: (Int, Float, Float) -> Float): Float {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun FloatArray.reduceOrNull(operation: (Float, Float) -> Float): Float? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> FloatArray.fold(initial: R, operation: (R, Float) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> FloatArray.foldIndexed(initial: R, operation: (Int, R, Float) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun FloatArray.find(predicate: (Float) -> Boolean): Float? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun FloatArray.findLast(predicate: (Float) -> Boolean): Float? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun FloatArray.first(): Float {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[0]
}

public fun FloatArray.first(predicate: (Float) -> Boolean): Float {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun FloatArray.firstOrNull(): Float? {
    if (this.size == 0) return null
    return this[0]
}

public fun FloatArray.firstOrNull(predicate: (Float) -> Boolean): Float? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun FloatArray.last(): Float {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[this.size - 1]
}

public fun FloatArray.last(predicate: (Float) -> Boolean): Float {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun FloatArray.lastOrNull(): Float? {
    if (this.size == 0) return null
    return this[this.size - 1]
}

public fun FloatArray.lastOrNull(predicate: (Float) -> Boolean): Float? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun FloatArray.any(): Boolean = this.size != 0

public fun FloatArray.any(predicate: (Float) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun FloatArray.all(predicate: (Float) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun FloatArray.none(): Boolean = this.size == 0

public fun FloatArray.none(predicate: (Float) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun FloatArray.count(): Int = this.size

public fun FloatArray.count(predicate: (Float) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}

public fun FloatArray.joinToString(separator: String = ", ", prefix: String = "", postfix: String = ""): String {
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

public fun FloatArray.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (Float) -> String
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

// --- BooleanArray ---

public fun <R> BooleanArray.map(transform: (Boolean) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <R> BooleanArray.mapIndexed(transform: (Int, Boolean) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <R : Any> BooleanArray.mapNotNull(transform: (Boolean) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <R> BooleanArray.flatMap(transform: (Boolean) -> List<R>): List<R> {
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

public fun BooleanArray.forEach(action: (Boolean) -> Unit) {
    var i = 0
    while (i < this.size) {
        action(this[i])
        i++
    }
}

public fun BooleanArray.filter(predicate: (Boolean) -> Boolean): List<Boolean> {
    val result = mutableListOf<Boolean>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun BooleanArray.filterIndexed(predicate: (Int, Boolean) -> Boolean): List<Boolean> {
    val result = mutableListOf<Boolean>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public fun BooleanArray.filterNot(predicate: (Boolean) -> Boolean): List<Boolean> {
    val result = mutableListOf<Boolean>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun BooleanArray.reduce(operation: (Boolean, Boolean) -> Boolean): Boolean {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun BooleanArray.reduceIndexed(operation: (Int, Boolean, Boolean) -> Boolean): Boolean {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun BooleanArray.reduceOrNull(operation: (Boolean, Boolean) -> Boolean): Boolean? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> BooleanArray.fold(initial: R, operation: (R, Boolean) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> BooleanArray.foldIndexed(initial: R, operation: (Int, R, Boolean) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun BooleanArray.find(predicate: (Boolean) -> Boolean): Boolean? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun BooleanArray.findLast(predicate: (Boolean) -> Boolean): Boolean? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun BooleanArray.first(): Boolean {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[0]
}

public fun BooleanArray.first(predicate: (Boolean) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun BooleanArray.firstOrNull(): Boolean? {
    if (this.size == 0) return null
    return this[0]
}

public fun BooleanArray.firstOrNull(predicate: (Boolean) -> Boolean): Boolean? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun BooleanArray.last(): Boolean {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[this.size - 1]
}

public fun BooleanArray.last(predicate: (Boolean) -> Boolean): Boolean {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun BooleanArray.lastOrNull(): Boolean? {
    if (this.size == 0) return null
    return this[this.size - 1]
}

public fun BooleanArray.lastOrNull(predicate: (Boolean) -> Boolean): Boolean? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun BooleanArray.any(): Boolean = this.size != 0

public fun BooleanArray.any(predicate: (Boolean) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun BooleanArray.all(predicate: (Boolean) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun BooleanArray.none(): Boolean = this.size == 0

public fun BooleanArray.none(predicate: (Boolean) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun BooleanArray.count(): Int = this.size

public fun BooleanArray.count(predicate: (Boolean) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}

public fun BooleanArray.joinToString(separator: String = ", ", prefix: String = "", postfix: String = ""): String {
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

public fun BooleanArray.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (Boolean) -> String
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

// --- CharArray ---

public fun <R> CharArray.map(transform: (Char) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <R> CharArray.mapIndexed(transform: (Int, Char) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <R : Any> CharArray.mapNotNull(transform: (Char) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <R> CharArray.flatMap(transform: (Char) -> List<R>): List<R> {
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

public fun CharArray.forEach(action: (Char) -> Unit) {
    var i = 0
    while (i < this.size) {
        action(this[i])
        i++
    }
}

public fun CharArray.filter(predicate: (Char) -> Boolean): List<Char> {
    val result = mutableListOf<Char>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun CharArray.filterIndexed(predicate: (Int, Char) -> Boolean): List<Char> {
    val result = mutableListOf<Char>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public fun CharArray.filterNot(predicate: (Char) -> Boolean): List<Char> {
    val result = mutableListOf<Char>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun CharArray.reduce(operation: (Char, Char) -> Char): Char {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun CharArray.reduceIndexed(operation: (Int, Char, Char) -> Char): Char {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun CharArray.reduceOrNull(operation: (Char, Char) -> Char): Char? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> CharArray.fold(initial: R, operation: (R, Char) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> CharArray.foldIndexed(initial: R, operation: (Int, R, Char) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun CharArray.find(predicate: (Char) -> Boolean): Char? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun CharArray.findLast(predicate: (Char) -> Boolean): Char? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun CharArray.first(): Char {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[0]
}

public fun CharArray.first(predicate: (Char) -> Boolean): Char {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun CharArray.firstOrNull(): Char? {
    if (this.size == 0) return null
    return this[0]
}

public fun CharArray.firstOrNull(predicate: (Char) -> Boolean): Char? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun CharArray.last(): Char {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[this.size - 1]
}

public fun CharArray.last(predicate: (Char) -> Boolean): Char {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun CharArray.lastOrNull(): Char? {
    if (this.size == 0) return null
    return this[this.size - 1]
}

public fun CharArray.lastOrNull(predicate: (Char) -> Boolean): Char? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun CharArray.any(): Boolean = this.size != 0

public fun CharArray.any(predicate: (Char) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun CharArray.all(predicate: (Char) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun CharArray.none(): Boolean = this.size == 0

public fun CharArray.none(predicate: (Char) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun CharArray.count(): Int = this.size

public fun CharArray.count(predicate: (Char) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}

public fun CharArray.joinToString(separator: String = ", ", prefix: String = "", postfix: String = ""): String {
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

public fun CharArray.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (Char) -> String
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

// --- UByteArray ---

public fun <R> UByteArray.map(transform: (UByte) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <R> UByteArray.mapIndexed(transform: (Int, UByte) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <R : Any> UByteArray.mapNotNull(transform: (UByte) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <R> UByteArray.flatMap(transform: (UByte) -> List<R>): List<R> {
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

public fun UByteArray.forEach(action: (UByte) -> Unit) {
    var i = 0
    while (i < this.size) {
        action(this[i])
        i++
    }
}

public fun UByteArray.filter(predicate: (UByte) -> Boolean): List<UByte> {
    val result = mutableListOf<UByte>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun UByteArray.filterIndexed(predicate: (Int, UByte) -> Boolean): List<UByte> {
    val result = mutableListOf<UByte>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public fun UByteArray.filterNot(predicate: (UByte) -> Boolean): List<UByte> {
    val result = mutableListOf<UByte>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun UByteArray.reduce(operation: (UByte, UByte) -> UByte): UByte {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun UByteArray.reduceIndexed(operation: (Int, UByte, UByte) -> UByte): UByte {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun UByteArray.reduceOrNull(operation: (UByte, UByte) -> UByte): UByte? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> UByteArray.fold(initial: R, operation: (R, UByte) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> UByteArray.foldIndexed(initial: R, operation: (Int, R, UByte) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun UByteArray.find(predicate: (UByte) -> Boolean): UByte? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun UByteArray.findLast(predicate: (UByte) -> Boolean): UByte? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun UByteArray.first(): UByte {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[0]
}

public fun UByteArray.first(predicate: (UByte) -> Boolean): UByte {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun UByteArray.firstOrNull(): UByte? {
    if (this.size == 0) return null
    return this[0]
}

public fun UByteArray.firstOrNull(predicate: (UByte) -> Boolean): UByte? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun UByteArray.last(): UByte {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[this.size - 1]
}

public fun UByteArray.last(predicate: (UByte) -> Boolean): UByte {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun UByteArray.lastOrNull(): UByte? {
    if (this.size == 0) return null
    return this[this.size - 1]
}

public fun UByteArray.lastOrNull(predicate: (UByte) -> Boolean): UByte? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun UByteArray.any(): Boolean = this.size != 0

public fun UByteArray.any(predicate: (UByte) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun UByteArray.all(predicate: (UByte) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun UByteArray.none(): Boolean = this.size == 0

public fun UByteArray.none(predicate: (UByte) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun UByteArray.count(): Int = this.size

public fun UByteArray.count(predicate: (UByte) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}

public fun UByteArray.joinToString(separator: String = ", ", prefix: String = "", postfix: String = ""): String {
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

public fun UByteArray.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (UByte) -> String
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

// --- UShortArray ---

public fun <R> UShortArray.map(transform: (UShort) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <R> UShortArray.mapIndexed(transform: (Int, UShort) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <R : Any> UShortArray.mapNotNull(transform: (UShort) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <R> UShortArray.flatMap(transform: (UShort) -> List<R>): List<R> {
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

public fun UShortArray.forEach(action: (UShort) -> Unit) {
    var i = 0
    while (i < this.size) {
        action(this[i])
        i++
    }
}

public fun UShortArray.filter(predicate: (UShort) -> Boolean): List<UShort> {
    val result = mutableListOf<UShort>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun UShortArray.filterIndexed(predicate: (Int, UShort) -> Boolean): List<UShort> {
    val result = mutableListOf<UShort>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public fun UShortArray.filterNot(predicate: (UShort) -> Boolean): List<UShort> {
    val result = mutableListOf<UShort>()
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun UShortArray.reduce(operation: (UShort, UShort) -> UShort): UShort {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun UShortArray.reduceIndexed(operation: (Int, UShort, UShort) -> UShort): UShort {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun UShortArray.reduceOrNull(operation: (UShort, UShort) -> UShort): UShort? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> UShortArray.fold(initial: R, operation: (R, UShort) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <R> UShortArray.foldIndexed(initial: R, operation: (Int, R, UShort) -> R): R {
    var acc = initial
    var i = 0
    while (i < this.size) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun UShortArray.find(predicate: (UShort) -> Boolean): UShort? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun UShortArray.findLast(predicate: (UShort) -> Boolean): UShort? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun UShortArray.first(): UShort {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[0]
}

public fun UShortArray.first(predicate: (UShort) -> Boolean): UShort {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun UShortArray.firstOrNull(): UShort? {
    if (this.size == 0) return null
    return this[0]
}

public fun UShortArray.firstOrNull(predicate: (UShort) -> Boolean): UShort? {
    var i = 0
    while (i < this.size) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun UShortArray.last(): UShort {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[this.size - 1]
}

public fun UShortArray.last(predicate: (UShort) -> Boolean): UShort {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun UShortArray.lastOrNull(): UShort? {
    if (this.size == 0) return null
    return this[this.size - 1]
}

public fun UShortArray.lastOrNull(predicate: (UShort) -> Boolean): UShort? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun UShortArray.any(): Boolean = this.size != 0

public fun UShortArray.any(predicate: (UShort) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun UShortArray.all(predicate: (UShort) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun UShortArray.none(): Boolean = this.size == 0

public fun UShortArray.none(predicate: (UShort) -> Boolean): Boolean {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun UShortArray.count(): Int = this.size

public fun UShortArray.count(predicate: (UShort) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}

public fun UShortArray.joinToString(separator: String = ", ", prefix: String = "", postfix: String = ""): String {
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

public fun UShortArray.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (UShort) -> String
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
