fun inspectCharProgression(p: CharProgression, other: Any?): String {
    val first: Char = p.first
    val last: Char = p.last
    val step: Int = p.step
    val iterator: CharIterator = p.iterator()
    val next: Char? = if (iterator.hasNext()) iterator.nextChar() else null
    val equal: Boolean = p.equals(other)
    val hash: Int = p.hashCode()
    return "${p.toString()}:$first,$last,$step,$next,$equal,$hash"
}

fun inheritedCharRangeIterator(r: CharRange): CharIterator = r.iterator()
