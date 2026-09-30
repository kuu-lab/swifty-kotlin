package kotlin.collections

// KUU-941: a primitive `vararg` parameter is a primitive array in the callee, so
// the aggregate that used to work only because it was typed as List<T> lives here.

public fun IntArray.sum(): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += this[i]
        i++
    }
    return sum
}

public fun LongArray.sum(): Long {
    var sum = 0L
    var i = 0
    while (i < this.size) {
        sum += this[i]
        i++
    }
    return sum
}

public fun ByteArray.sum(): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += this[i].toInt()
        i++
    }
    return sum
}

public fun ShortArray.sum(): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += this[i].toInt()
        i++
    }
    return sum
}

public fun DoubleArray.sum(): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += this[i]
        i++
    }
    return sum
}

public fun FloatArray.sum(): Float {
    var sum = 0.0f
    var i = 0
    while (i < this.size) {
        sum += this[i]
        i++
    }
    return sum
}
