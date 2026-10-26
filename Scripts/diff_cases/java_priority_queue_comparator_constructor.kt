// KUU-3484: one-argument comparator constructors must retain and invoke the comparator.
fun main() {
    println(java.util.PriorityQueue<Int>(compareBy { -it })
        .also { it.add(1); it.add(2) }.peek())
    println(java.util.PriorityQueue<Int>(Comparator<Int> { a, b -> b - a })
        .also { it.add(1); it.add(2) }.peek())
}
