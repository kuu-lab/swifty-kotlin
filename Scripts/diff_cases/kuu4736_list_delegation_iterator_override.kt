// DIFF_JVM
// DIFF_SKIP_NATIVE: JVM-lane regression for the JVM collections declaration surface
// KUU-4736: a class delegating to List<Int> may covariantly override the
// inherited iterator() with Iterator<Int>. The override intentionally ignores
// the delegate so semantic dispatch is observable in the output.
class ArrayView(delegate: List<Int>) : List<Int> by delegate {
    override fun iterator(): Iterator<Int> = listOf(8, 9).iterator()
}

fun main() {
    println(ArrayView(listOf(1, 2)).iterator().next())
}
