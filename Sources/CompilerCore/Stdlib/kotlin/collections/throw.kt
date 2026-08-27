package kotlin.collections

@PublishedApi
@SinceKotlin("1.3")
internal fun throwIndexOverflow() { throw ArithmeticException("Index overflow has happened.") }

@PublishedApi
@SinceKotlin("1.3")
internal fun throwCountOverflow() { throw ArithmeticException("Count overflow has happened.") }
