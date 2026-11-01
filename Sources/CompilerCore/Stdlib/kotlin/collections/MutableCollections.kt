package kotlin.collections

// KUU-1394: on JVM these resolve as java.util.SequencedCollection members of
// List (JDK 21+); ArrayDeque declares them as class members. They are
// source-backed MutableList extensions here, matching the removeFirst/
// removeLast handling below.
public fun <T> MutableList<T>.addFirst(element: T) {
    add(0, element)
}

public fun <T> MutableList<T>.addLast(element: T) {
    add(element)
}

// KSP-1503: MutableList's removal helpers delegate to the source-backed
// removeAt member, whose default body retains the runtime bridge at the
// storage boundary.

@SinceKotlin("1.4")
@IgnorableReturnValue
public fun <T> MutableList<T>.removeFirst(): T {
    if (isEmpty()) throw NoSuchElementException()
    return removeAt(0)
}

@SinceKotlin("1.4")
@IgnorableReturnValue
public fun <T> MutableList<T>.removeFirstOrNull(): T? {
    if (isEmpty()) return null
    return removeAt(0)
}

@SinceKotlin("1.4")
@IgnorableReturnValue
public fun <T> MutableList<T>.removeLast(): T {
    if (isEmpty()) throw NoSuchElementException()
    return removeAt(size - 1)
}

@SinceKotlin("1.4")
@IgnorableReturnValue
public fun <T> MutableList<T>.removeLastOrNull(): T? {
    if (isEmpty()) return null
    return removeAt(size - 1)
}

// KUU-4026: on JVM removeIf resolves as the java.util.Collection default
// method, so the receiver is MutableCollection — covering MutableList,
// MutableSet, and the MutableMap entries/keys/values views. Removal goes
// through MutableIterator.remove, matching the JDK implementation.
@IgnorableReturnValue
public fun <T> MutableCollection<T>.removeIf(predicate: (T) -> Boolean): Boolean {
    var changed = false
    val iterator = iterator()
    while (iterator.hasNext()) {
        if (predicate(iterator.next())) {
            iterator.remove()
            changed = true
        }
    }
    return changed
}

// KSP-436: Direct storage mutation stays in the `__kk_mutable_*` bridges; the
// functions below are expressed in terms of the `size` / `get` / `set`
// members that reach those bridges.

public fun <T> MutableList<T>.replaceAll(transform: (T) -> T) {
    var index = 0
    while (index < size) {
        this[index] = transform(this[index])
        index += 1
    }
}

public fun <T> MutableList<T>.fill(value: T) {
    var index = 0
    while (index < size) {
        this[index] = value
        index += 1
    }
}
