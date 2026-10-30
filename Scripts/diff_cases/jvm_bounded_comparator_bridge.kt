// DIFF_JVM: Verify erased bridges for anonymous bounded generic overrides.
private fun <T : Comparable<T>> descending(): Comparator<T> = object : Comparator<T> {
    override fun compare(a: T, b: T): Int = b.compareTo(a)
}

private interface Measure<T> { fun size(value: T): Int }
private fun <T : CharSequence> measure(): Measure<T> = object : Measure<T> {
    override fun size(value: T): Int = value.length
}
private class Wrong

fun main() {
    val comparator = descending<String>()
    println(comparator.compare("a", "b"))
    println(measure<String>().size("abc"))
    @Suppress("UNCHECKED_CAST")
    val wrongComparator = comparator as Comparator<Any>
    try { wrongComparator.compare(Wrong(), Wrong()); println("unexpected") }
    catch (e: ClassCastException) { println("comparator cast") }
    @Suppress("UNCHECKED_CAST")
    val wrongMeasure = measure<String>() as Measure<Any>
    try { wrongMeasure.size(Wrong()); println("unexpected") }
    catch (e: ClassCastException) { println("measure cast") }
}
