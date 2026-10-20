package kotlin.collections

import kotlin.sequences.*
import kotlin.sequences.emptySequence
import kotlin.sequences.joinToString

public fun <T> Array<out T>.asSequence(): Sequence<T> {
    if (this.size == 0) return emptySequence<T>()
    val source = this
    return object: Sequence<T> {
        override fun iterator(): Iterator<T> = object: Iterator<T> {
            var index = 0
            override fun hasNext(): Boolean = index < source.size
            override fun next(): T {
                if (!hasNext()) throw NoSuchElementException()
                val element = source[index]
                index++
                return element
            }
        }
    }
}
public fun <T> Array<out T>.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((T) -> CharSequence)? = null): String = this.asSequence().joinToString(separator, prefix, postfix, limit, truncated, transform)

public fun IntArray.asSequence(): Sequence<Int> {
    if (this.size == 0) return emptySequence<Int>()
    val source = this
    return object: Sequence<Int> {
        override fun iterator(): Iterator<Int> = object: Iterator<Int> {
            var index = 0
            override fun hasNext(): Boolean = index < source.size
            override fun next(): Int {
                if (!hasNext()) throw NoSuchElementException()
                val element = source[index]
                index++
                return element
            }
        }
    }
}
public fun IntArray.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((Int) -> CharSequence)? = null): String = this.asSequence().joinToString(separator, prefix, postfix, limit, truncated, transform)

public fun LongArray.asSequence(): Sequence<Long> {
    if (this.size == 0) return emptySequence<Long>()
    val source = this
    return object: Sequence<Long> {
        override fun iterator(): Iterator<Long> = object: Iterator<Long> {
            var index = 0
            override fun hasNext(): Boolean = index < source.size
            override fun next(): Long {
                if (!hasNext()) throw NoSuchElementException()
                val element = source[index]
                index++
                return element
            }
        }
    }
}
public fun LongArray.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((Long) -> CharSequence)? = null): String = this.asSequence().joinToString(separator, prefix, postfix, limit, truncated, transform)

public fun FloatArray.asSequence(): Sequence<Float> {
    if (this.size == 0) return emptySequence<Float>()
    val source = this
    return object: Sequence<Float> {
        override fun iterator(): Iterator<Float> = object: Iterator<Float> {
            var index = 0
            override fun hasNext(): Boolean = index < source.size
            override fun next(): Float {
                if (!hasNext()) throw NoSuchElementException()
                val element = source[index]
                index++
                return element
            }
        }
    }
}
public fun FloatArray.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((Float) -> CharSequence)? = null): String = this.asSequence().joinToString(separator, prefix, postfix, limit, truncated, transform)

public fun DoubleArray.asSequence(): Sequence<Double> {
    if (this.size == 0) return emptySequence<Double>()
    val source = this
    return object: Sequence<Double> {
        override fun iterator(): Iterator<Double> = object: Iterator<Double> {
            var index = 0
            override fun hasNext(): Boolean = index < source.size
            override fun next(): Double {
                if (!hasNext()) throw NoSuchElementException()
                val element = source[index]
                index++
                return element
            }
        }
    }
}
public fun DoubleArray.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((Double) -> CharSequence)? = null): String = this.asSequence().joinToString(separator, prefix, postfix, limit, truncated, transform)

public fun BooleanArray.asSequence(): Sequence<Boolean> {
    if (this.size == 0) return emptySequence<Boolean>()
    val source = this
    return object: Sequence<Boolean> {
        override fun iterator(): Iterator<Boolean> = object: Iterator<Boolean> {
            var index = 0
            override fun hasNext(): Boolean = index < source.size
            override fun next(): Boolean {
                if (!hasNext()) throw NoSuchElementException()
                val element = source[index]
                index++
                return element
            }
        }
    }
}
public fun BooleanArray.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((Boolean) -> CharSequence)? = null): String = this.asSequence().joinToString(separator, prefix, postfix, limit, truncated, transform)

public fun CharArray.asSequence(): Sequence<Char> {
    if (this.size == 0) return emptySequence<Char>()
    val source = this
    return object: Sequence<Char> {
        override fun iterator(): Iterator<Char> = object: Iterator<Char> {
            var index = 0
            override fun hasNext(): Boolean = index < source.size
            override fun next(): Char {
                if (!hasNext()) throw NoSuchElementException()
                val element = source[index]
                index++
                return element
            }
        }
    }
}
public fun CharArray.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((Char) -> CharSequence)? = null): String = this.asSequence().joinToString(separator, prefix, postfix, limit, truncated, transform)

public fun ByteArray.asSequence(): Sequence<Byte> {
    if (this.size == 0) return emptySequence<Byte>()
    val source = this
    return object: Sequence<Byte> {
        override fun iterator(): Iterator<Byte> = object: Iterator<Byte> {
            var index = 0
            override fun hasNext(): Boolean = index < source.size
            override fun next(): Byte {
                if (!hasNext()) throw NoSuchElementException()
                val element = source[index]
                index++
                return element
            }
        }
    }
}
public fun ByteArray.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((Byte) -> CharSequence)? = null): String = this.asSequence().joinToString(separator, prefix, postfix, limit, truncated, transform)

public fun ShortArray.asSequence(): Sequence<Short> {
    if (this.size == 0) return emptySequence<Short>()
    val source = this
    return object: Sequence<Short> {
        override fun iterator(): Iterator<Short> = object: Iterator<Short> {
            var index = 0
            override fun hasNext(): Boolean = index < source.size
            override fun next(): Short {
                if (!hasNext()) throw NoSuchElementException()
                val element = source[index]
                index++
                return element
            }
        }
    }
}
public fun ShortArray.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((Short) -> CharSequence)? = null): String = this.asSequence().joinToString(separator, prefix, postfix, limit, truncated, transform)

fun <T> Array<out T>.toList(): List<T> = this.asSequence().toList()
fun <T> Array<out T>.toMutableList(): MutableList<T> = this.asSequence().toMutableList()
fun <T> Array<out T>.toSet(): Set<T> = this.asSequence().toSet()
fun <T> Array<out T>.toMutableSet(): MutableSet<T> = this.asSequence().toMutableSet()

fun <T> Array<out T>.isEmpty(): Boolean = this.size == 0

@kotlin.jvm.JvmName("getIndices")
fun <T> Array<out T>.arrayIndices(): kotlin.ranges.IntRange = kotlin.ranges.IntRange(0, this.size - 1)
@kotlin.jvm.JvmName("getIndices")
fun IntArray.arrayIndices(): kotlin.ranges.IntRange = kotlin.ranges.IntRange(0, this.size - 1)
