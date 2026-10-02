fun main() {
    var arr = intArrayOf(1, 2, 3)
    for (x in arr) { arr = intArrayOf(10, 20, 30, 40); print("$x ") }
    println()
    var shorter = intArrayOf(1, 2, 3)
    for (x in shorter) { shorter = intArrayOf(9); print("$x ") }
    println()
}
