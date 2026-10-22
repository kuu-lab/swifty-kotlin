// KUU-2791: synchronized is inline, so a bare return inside its block exits the caller.
fun find(data: IntArray): Int {
    synchronized(data) {
        return 42
    }
}

fun findLocal(data: IntArray): Int = synchronized(data) {
    return@synchronized 5
}

fun main() {
    println(find(intArrayOf(1)))
    println(findLocal(intArrayOf(1)))
}
