fun main() {
    val cmp = Comparator<Int> { a, b -> a.compareTo(b) }
    println(cmp.compare(3, 5))
    println(cmp.compare(7, 2))
    println(cmp.compare(4, 4))
}
