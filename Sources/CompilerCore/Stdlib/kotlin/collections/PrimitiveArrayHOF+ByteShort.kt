package kotlin.collections

// KSP-687: primitive array higher-order functions are bundled Kotlin source.
// The generated-looking repetition mirrors Kotlin's specialized primitive-array API.
// It keeps element values typed at the source boundary instead of passing raw words
// through the former kk_array_* runtime HOF bridges.

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

public fun ByteArray.single(): Byte {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    if (this.size != 1) throw IllegalArgumentException("Array has more than one element.")
    return this[0]
}

public fun ByteArray.singleOrNull(): Byte? = if (this.size == 1) this[0] else null

public inline fun ByteArray.single(predicate: (Byte) -> Boolean): Byte {
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

public inline fun ByteArray.singleOrNull(predicate: (Byte) -> Boolean): Byte? {
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

public fun ShortArray.single(): Short {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    if (this.size != 1) throw IllegalArgumentException("Array has more than one element.")
    return this[0]
}

public fun ShortArray.singleOrNull(): Short? = if (this.size == 1) this[0] else null

public inline fun ShortArray.single(predicate: (Short) -> Boolean): Short {
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

public inline fun ShortArray.singleOrNull(predicate: (Short) -> Boolean): Short? {
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
