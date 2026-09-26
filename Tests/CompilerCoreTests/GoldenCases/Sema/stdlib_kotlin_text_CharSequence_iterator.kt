package golden.sema

fun charSequenceIterator(source: CharSequence): CharIterator = source.iterator()

fun stringIterator(): CharIterator = "abc".iterator()

fun stringBuilderIterator(source: StringBuilder): CharIterator = source.iterator()

fun charSequenceForLoop(source: CharSequence): Char {
    for (c in source) return c
    return '?'
}

fun charSequenceIteratorProtocol(source: CharSequence): Char {
    val iterator = source.iterator()
    return if (iterator.hasNext()) iterator.nextChar() else '?'
}
