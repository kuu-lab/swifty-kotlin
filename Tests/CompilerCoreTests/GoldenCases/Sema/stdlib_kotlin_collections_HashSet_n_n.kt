fun hashSetConstructors(): Int {
    val empty = HashSet<String>()
    val sized = HashSet<String>(8)
    val copied = HashSet(listOf("a", "b"))
    val tuned = HashSet<String>(8, 0.75f)
    return empty.size + sized.size + copied.size + tuned.size
}
