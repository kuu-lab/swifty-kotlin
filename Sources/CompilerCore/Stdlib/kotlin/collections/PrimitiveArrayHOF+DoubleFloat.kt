package kotlin.collections

// KSP-687: primitive array higher-order functions are bundled Kotlin source.
// The generated-looking repetition mirrors Kotlin's specialized primitive-array API.
// It keeps element values typed at the source boundary instead of passing raw words
// through the former kk_array_* runtime HOF bridges.

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

public fun DoubleArray.single(): Double {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    if (this.size != 1) throw IllegalArgumentException("Array has more than one element.")
    return this[0]
}

public fun DoubleArray.singleOrNull(): Double? = if (this.size == 1) this[0] else null

public inline fun DoubleArray.single(predicate: (Double) -> Boolean): Double {
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

public inline fun DoubleArray.singleOrNull(predicate: (Double) -> Boolean): Double? {
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

public fun FloatArray.single(): Float {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    if (this.size != 1) throw IllegalArgumentException("Array has more than one element.")
    return this[0]
}

public fun FloatArray.singleOrNull(): Float? = if (this.size == 1) this[0] else null

public inline fun FloatArray.single(predicate: (Float) -> Boolean): Float {
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

public inline fun FloatArray.singleOrNull(predicate: (Float) -> Boolean): Float? {
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
