package kotlin.collections

@PublishedApi
@SinceKotlin("1.3")
@IgnorableReturnValue
internal inline fun checkIndexOverflow(index: Int): Int {
    if (index < 0) {
        throwIndexOverflow()
    }
    return index
}

@PublishedApi
@SinceKotlin("1.3")
@IgnorableReturnValue
internal inline fun checkCountOverflow(count: Int): Int {
    if (count < 0) {
        throwCountOverflow()
    }
    return count
}

@PublishedApi
@SinceKotlin("1.3")
internal fun throwIndexOverflow() {
    throw ArithmeticException("Index overflow has happened.")
}

@PublishedApi
@SinceKotlin("1.3")
internal fun throwCountOverflow() {
    throw ArithmeticException("Count overflow has happened.")
}

