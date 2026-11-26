// DIFF_JVM
// KUU-4730: JVM consumers resolve and run both setOfNotNull overloads.

fun main() {
    val missing: String? = null
    val present: String? = "one"

    println(setOfNotNull(missing))
    println(setOfNotNull(present))
    println(setOfNotNull(missing, "two", present, missing, "two"))

    val values: Array<String?> = arrayOf(null, "three", "three", null)
    println(setOfNotNull(*values))
    println(setOfNotNull<String>())
}
