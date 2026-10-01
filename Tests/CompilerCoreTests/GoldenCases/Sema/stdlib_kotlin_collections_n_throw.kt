package golden.sema
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
fun countOverflowReturnsUnit(): Unit = kotlin.collections.throwCountOverflow()

fun indexOverflowReturnsUnit(): Unit = kotlin.collections.throwIndexOverflow()

fun countOverflowAsStatement(): Unit {
    kotlin.collections.throwCountOverflow()
}

fun indexOverflowAsStatement(): Unit {
    kotlin.collections.throwIndexOverflow()
}
