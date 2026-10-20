package kotlin
fun interface Comparator<in T> { fun compare(a: T, b: T): Int }
