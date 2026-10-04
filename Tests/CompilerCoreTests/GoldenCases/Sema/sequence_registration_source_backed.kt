fun normalize(input: Sequence<Int>?): Int {
    val value = input.orEmpty()
    val iterator = value.iterator()
    return iterator.next()
}
