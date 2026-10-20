package kotlin.sequences
interface Sequence<out T> { operator fun iterator(): Iterator<T> }