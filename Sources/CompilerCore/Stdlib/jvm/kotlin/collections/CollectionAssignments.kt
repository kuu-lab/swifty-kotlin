@file:kotlin.jvm.JvmName("CollectionsKt")
package kotlin.collections

public inline operator fun <T> MutableCollection<in T>.plusAssign(element: T) {
    this.add(element)
}
public inline operator fun <T> MutableCollection<in T>.plusAssign(elements: Iterable<T>) {
    this.addAll(elements)
}
public inline operator fun <T> MutableCollection<in T>.plusAssign(elements: Array<T>) {
    this.addAll(elements)
}
public inline operator fun <T> MutableCollection<in T>.plusAssign(elements: kotlin.sequences.Sequence<T>) {
    this.addAll(elements)
}
public inline operator fun <T> MutableCollection<in T>.minusAssign(element: T) {
    this.remove(element)
}
public inline operator fun <T> MutableCollection<in T>.minusAssign(elements: Iterable<T>) {
    this.removeAll(elements)
}
public inline operator fun <T> MutableCollection<in T>.minusAssign(elements: Array<T>) {
    this.removeAll(elements)
}
public inline operator fun <T> MutableCollection<in T>.minusAssign(elements: kotlin.sequences.Sequence<T>) {
    this.removeAll(elements)
}
