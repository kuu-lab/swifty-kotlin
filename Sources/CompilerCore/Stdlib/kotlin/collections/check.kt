package kotlin.collections

@PublishedApi
@SinceKotlin("1.3")
@IgnorableReturnValue
internal inline fun checkIndexOverflow(index: Int): Int {
    if (index < 0) {
        throw ArithmeticException("Index overflow has happened.")
    }
    return index
}

