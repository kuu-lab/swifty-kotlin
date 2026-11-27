@file:kotlin.jvm.JvmName("CollectionsKt")

package kotlin.collections

import kotlin.random.Random

public fun <T> MutableList<T>.sortWith(comparator: Comparator<in T>) {
    if (size > 1) java.util.Collections.sort<T>(this, comparator as java.util.Comparator<T>)
}

public fun <T> MutableList<T>.removeFirst(): T {
    if (isEmpty()) throw NoSuchElementException("List is empty.")
    return removeAt(0)
}

public fun <T> MutableList<T>.removeLast(): T {
    if (isEmpty()) throw NoSuchElementException("List is empty.")
    return removeAt(size - 1)
}

public fun <T> MutableList<T>.replaceAll(transform: (T) -> T) {
    var index = 0
    while (index < size) {
        this[index] = transform(this[index])
        index += 1
    }
}

public fun <T> MutableList<T>.removeFirstOrNull(): T? = if (isEmpty()) null else removeAt(0)

public fun <T> MutableList<T>.removeLastOrNull(): T? = if (isEmpty()) null else removeAt(size - 1)

// Delegate to the JDK like kotlinc: java.util.Collections walks LinkedList
// with iterators, whereas index-based swaps would be quadratic there.
public fun <T> MutableList<T>.reverse() {
    java.util.Collections.reverse<T>(this)
}

public fun <T> MutableList<T>.shuffle() {
    java.util.Collections.shuffle<T>(this)
}

// Same swap order as java.util.Collections.shuffle, which Kotlin/JVM delegates
// to, so a seeded Random yields the same permutation as kotlinc.
public fun <T> MutableList<T>.shuffle(random: Random) {
    var index = size - 1
    while (index > 0) {
        val other = random.nextInt(index + 1)
        val value = this[index]
        this[index] = this[other]
        this[other] = value
        index--
    }
}
