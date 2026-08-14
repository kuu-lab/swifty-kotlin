package kotlin.sequences

// KSP-446
// Sequence destination-collection higher-order functions migrated to Kotlin source.

public fun <T, C : MutableCollection<T>> Sequence<T>.filterTo(
    destination: C,
    predicate: (T) -> Boolean
): C {
    val iterator = this.iterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (predicate(element)) destination.add(element)
    }
    return destination
}

public fun <T, C : MutableCollection<T>> Sequence<T>.filterNotTo(
    destination: C,
    predicate: (T) -> Boolean
): C {
    val iterator = this.iterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (!predicate(element)) destination.add(element)
    }
    return destination
}

public fun <T, R, C : MutableCollection<R>> Sequence<T>.mapTo(
    destination: C,
    transform: (T) -> R
): C {
    val iterator = this.iterator()
    while (iterator.hasNext()) destination.add(transform(iterator.next()))
    return destination
}

public fun <T, R : Any, C : MutableCollection<R>> Sequence<T>.mapNotNullTo(
    destination: C,
    transform: (T) -> R?
): C {
    val iterator = this.iterator()
    while (iterator.hasNext()) {
        val item = transform(iterator.next())
        if (item != null) destination.add(item)
    }
    return destination
}

public fun <T, R, C : MutableCollection<R>> Sequence<T>.mapIndexedTo(
    destination: C,
    transform: (Int, T) -> R
): C {
    val iterator = this.iterator()
    var index = 0
    while (iterator.hasNext()) {
        destination.add(transform(index, iterator.next()))
        index = index + 1
    }
    return destination
}

public fun <T, R, C : MutableCollection<R>> Sequence<T>.flatMapTo(
    destination: C,
    transform: (T) -> Iterable<R>
): C {
    val iterator = this.iterator()
    while (iterator.hasNext()) {
        val nestedIterator = transform(iterator.next()).iterator()
        while (nestedIterator.hasNext()) destination.add(nestedIterator.next())
    }
    return destination
}

public fun <T, C : MutableCollection<T>> Sequence<T>.filterIndexedTo(
    destination: C,
    predicate: (Int, T) -> Boolean
): C {
    val iterator = this.iterator()
    var index = 0
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (predicate(index, element)) destination.add(element)
        index = index + 1
    }
    return destination
}

public fun <T, R : Any, C : MutableCollection<R>> Sequence<T>.mapIndexedNotNullTo(
    destination: C,
    transform: (Int, T) -> R?
): C {
    val iterator = this.iterator()
    var index = 0
    while (iterator.hasNext()) {
        val item = transform(index, iterator.next())
        if (item != null) destination.add(item)
        index = index + 1
    }
    return destination
}

public fun <T, R, C : MutableCollection<R>> Sequence<T>.flatMapIndexedTo(
    destination: C,
    transform: (Int, T) -> Iterable<R>
): C {
    val iterator = this.iterator()
    var index = 0
    while (iterator.hasNext()) {
        val nestedIterator = transform(index, iterator.next()).iterator()
        while (nestedIterator.hasNext()) destination.add(nestedIterator.next())
        index = index + 1
    }
    return destination
}

public fun <T : Any, C : MutableCollection<T>> Sequence<T?>.filterNotNullTo(
    destination: C
): C {
    val iterator = this.iterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (element != null) destination.add(element)
    }
    return destination
}

public inline fun <reified R : Any, C : MutableCollection<R>> Sequence<*>.filterIsInstanceTo(
    destination: C
): C {
    val iterator = this.iterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (element is R) destination.add(element)
    }
    return destination
}
