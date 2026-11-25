// DIFF_JVM
// JVM ArrayList is a java.util.ArrayList typealias; capacity and collection
// constructors must lower to JDK constructors (paging-common Separators.kt).
fun main() {
    val byCapacity = ArrayList<Int>(4)
    byCapacity.add(1)
    println(byCapacity.size)
    val copied = ArrayList<Int>(byCapacity)
    println(copied.size)
}
