package golden.sema

fun iterableFactory(): Iterable<Int> {
    val values: Iterable<Int> = Iterable { listOf(3, 1, 2).iterator() }
    return values
}

fun iterableFactoryNamed(): Iterable<Int> {
    return Iterable(iterator = { listOf(1).iterator() })
}
