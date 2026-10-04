package kotlin.collections

// KSP-953: keep the collection ifEmpty overloads source-backed while preserving
// Kotlin's self-type constraint so a non-empty receiver is returned unchanged.

public inline fun <C, R> C.ifEmpty(defaultValue: () -> R): R where C : Collection<*>, C : R {
    return if (this.size == 0) defaultValue() else this
}

public inline fun <M, R> M.ifEmpty(defaultValue: () -> R): R where M : Map<*, *>, M : R {
    return if (this.size == 0) defaultValue() else this
}

public inline fun <C, R> C.ifEmpty(defaultValue: () -> R): R where C : Array<*>, C : R {
    return if (this.size == 0) defaultValue() else this
}
