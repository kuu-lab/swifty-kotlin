fun main() {
    val extreme = Comparator<Int> { a, b -> if (a == b) 0 else if (a < b) Int.MIN_VALUE else 1 }
    println(listOf(3, 1, 2).sortedWith(extreme))
    println(listOf(3, 1, 2).sortedWith(extreme.reversed()))
    println(extreme.reversed().compare(1, 2))
    println(extreme.reversed().compare(2, 1))
    println(extreme.reversed().compare(2, 2))

    val byLength = compareBy<String> { it.length }
    println(listOf("bb", "a", "ccc").sortedWith(byLength.reversed()))
    println(listOf("bb", "a", "ccc").sortedWith(byLength.reversed().reversed()))
}
