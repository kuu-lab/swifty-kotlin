package kotlin
interface Comparable<in T> { operator fun compareTo(other: T): Int }
