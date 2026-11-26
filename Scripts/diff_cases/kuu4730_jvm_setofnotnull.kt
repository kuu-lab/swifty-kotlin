// DIFF_JVM
// KUU-4730: JVM consumers resolve and run both setOfNotNull overloads.

private fun <T> probeRemove(name: String, values: Set<T>) {
    val iterator = values.iterator()
    if (iterator.hasNext()) iterator.next()
    try {
        (iterator as MutableIterator<T>).remove()
        println(name + ":removed:" + values)
    } catch (e: UnsupportedOperationException) {
        println(name + ":uoe:" + values)
    }
}

fun main() {
    val missing: String? = null
    val present: String? = "one"

    println(setOfNotNull(missing))
    println(setOfNotNull(present))
    println(setOfNotNull(missing, "two", present, missing, "two"))

    val values: Array<String?> = arrayOf(null, "three", "three", null)
    println(setOfNotNull(*values))
    println(setOfNotNull<String>())

    probeRemove("single", setOfNotNull(present))
    probeRemove("spreadSingle", setOfNotNull(*arrayOf(present)))
}
