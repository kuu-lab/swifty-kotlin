fun main() {
    val l: List<Int>? = listOf(1)
    println(l?.get(0))
    println(l?.get(0)?.plus(1))
    val deep: Map<String, List<Map<Int, String>>> =
        mapOf("k" to listOf(mapOf(1 to "v")))
    println(deep["k"]?.get(0)?.get(1))
    // Same receiver shape through the sibling members gated by the fix.
    println(l?.indexOf(1)?.inc())
    println(l?.subList(0, 1)?.get(0)?.plus(5))
    val ml: MutableList<Int>? = mutableListOf(4)
    println(ml?.get(0)?.plus(1))
    val li: List<Int> = listOf(2)
    val x: Int = li.get(0)
    println(x + li.get(0).plus(3))
}
