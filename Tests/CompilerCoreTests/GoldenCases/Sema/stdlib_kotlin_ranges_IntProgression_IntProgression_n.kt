fun inspectIntProgression(progression: IntProgression, other: Any?) {
    val first: Int = progression.first
    val last: Int = progression.last
    val step: Int = progression.step
    val iterator: IntIterator = progression.iterator()
    println("$first,$last,$step")
    println(progression.equals(other))
    println(progression.hashCode())
    println(progression.toString())
    println(progression == other)
    if (iterator.hasNext()) println(iterator.nextInt())
}
