package kotlin.collections

// KSP-687: primitive array higher-order functions are bundled Kotlin source.
// The generated-looking repetition mirrors Kotlin's specialized primitive-array API.
// It keeps element values typed at the source boundary instead of passing raw words
// through the former kk_array_* runtime HOF bridges.

// --- UByteArray ---

public fun UByteArray.elementAt(index: Int): UByte = this[index]

public fun UByteArray.getOrNull(index: Int): UByte? =
    if (index >= 0 && index < size) this[index] else null

public inline fun UByteArray.elementAtOrElse(index: Int, defaultValue: (Int) -> UByte): UByte =
    if (index >= 0 && index < size) this[index] else defaultValue(index)

public inline fun UByteArray.indexOfFirst(predicate: (UByte) -> Boolean): Int {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return i
        i++
    }
    return -1
}

public inline fun UByteArray.indexOfLast(predicate: (UByte) -> Boolean): Int {
    var i = this.size - 1
    while (i >= 0) {
        if (predicate(this[i])) return i
        i--
    }
    return -1
}

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

public fun UByteArray.single(): UByte {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    if (this.size != 1) throw IllegalArgumentException("Array has more than one element.")
    return this[0]
}

public fun UByteArray.singleOrNull(): UByte? = if (this.size == 1) this[0] else null

public inline fun UByteArray.single(predicate: (UByte) -> Boolean): UByte {
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

public inline fun UByteArray.singleOrNull(predicate: (UByte) -> Boolean): UByte? {
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

public fun UShortArray.elementAt(index: Int): UShort = this[index]

public fun UShortArray.getOrNull(index: Int): UShort? =
    if (index >= 0 && index < size) this[index] else null

public inline fun UShortArray.elementAtOrElse(index: Int, defaultValue: (Int) -> UShort): UShort =
    if (index >= 0 && index < size) this[index] else defaultValue(index)

public inline fun UShortArray.indexOfFirst(predicate: (UShort) -> Boolean): Int {
    var i = 0
    while (i < this.size) {
        if (predicate(this[i])) return i
        i++
    }
    return -1
}

public inline fun UShortArray.indexOfLast(predicate: (UShort) -> Boolean): Int {
    var i = this.size - 1
    while (i >= 0) {
        if (predicate(this[i])) return i
        i--
    }
    return -1
}

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

public fun UShortArray.single(): UShort {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    if (this.size != 1) throw IllegalArgumentException("Array has more than one element.")
    return this[0]
}

public fun UShortArray.singleOrNull(): UShort? = if (this.size == 1) this[0] else null

public inline fun UShortArray.single(predicate: (UShort) -> Boolean): UShort {
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

public inline fun UShortArray.singleOrNull(predicate: (UShort) -> Boolean): UShort? {
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
