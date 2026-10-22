fun source(): Iterable<Int> { print("R"); return listOf(1, 2, 3) }
fun predicate(): (Int) -> Boolean { print("P"); return { print(it); it == 2 } }
fun leaveInline(): Int {
    listOf(1, 2).first { if (it == 2) return 9; false }
    return -1
}
fun positive(value: Int): Boolean = value > 0
fun main() {
    println(source().first(predicate()))
    println(listOf<String?>("a", null, "c").first { it == null })
    println(listOf(-1, 2, 3).first(::positive))
    println(leaveInline())
    var calls = 0
    try { listOf(1, 2).first { calls++; false } }
    catch (failure: NoSuchElementException) { println(failure.message) }
    println(calls)
    try { emptyList<Int>().first { calls++; true } }
    catch (failure: NoSuchElementException) { println(failure.message) }
    println(calls)
    try { listOf(1, 2, 3).first { print(it); throw IllegalStateException("predicate") } }
    catch (failure: IllegalStateException) { println(failure.message) }
}
