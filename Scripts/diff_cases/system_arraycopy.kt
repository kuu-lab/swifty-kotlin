// KUU-2223: JVM-compatible System.arraycopy for reference and primitive arrays.
fun main() {
    val source = arrayOf("zero", "one", "two", "three")
    val destination = arrayOf("a", "b", "c", "d", "e")
    System.arraycopy(source, 1, destination, 2, 2)
    println(destination.toList())

    val boxedInts = arrayOf(7, 8)
    val comparableDestination = arrayOfNulls<Comparable<*>>(boxedInts.size)
    System.arraycopy(boxedInts, 0, comparableDestination, 0, boxedInts.size)
    println(comparableDestination.toList())

    val overlap = arrayOf(1, 2, 3, 4, 5)
    System.arraycopy(overlap, 0, overlap, 1, 4)
    println(overlap.toList())
    System.arraycopy(source, source.size, destination, destination.size, 0)
    println("zero-length-ok")

    try {
        System.arraycopy(source, 3, destination, 0, 2)
        println("no-range-error")
    } catch (e: ArrayIndexOutOfBoundsException) {
        println("range-error")
    }
    try {
        System.arraycopy(source, 0, destination, 0, -1)
        println("no-negative-length-error")
    } catch (e: ArrayIndexOutOfBoundsException) {
        println("negative-length-error")
    }

    val mixed: Array<Any?> = arrayOf("copied", 42)
    val strings = arrayOf("old", "kept")
    try {
        System.arraycopy(mixed, 0, strings, 0, mixed.size)
        println("no-store-error")
    } catch (e: java.lang.ArrayStoreException) {
        println("store-error")
    }
    println(strings.toList())

    val intSource = intArrayOf(7, 8, 9)
    val intDestination = intArrayOf(0, 0, 0, 0)
    System.arraycopy(intSource, 1, intDestination, 0, 2)
    println(intDestination.toList())
    try {
        System.arraycopy(intSource, 0, longArrayOf(0L, 0L, 0L), 0, 1)
        println("no-primitive-store-error")
    } catch (e: java.lang.ArrayStoreException) {
        println("primitive-store-error")
    }

    val nullSource: Any? = null
    try {
        System.arraycopy(nullSource, 0, strings, 0, 0)
        println("no-null-error")
    } catch (e: NullPointerException) {
        println("null-error")
    }
}
