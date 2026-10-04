fun main() {
    val p = 1 to "one"
    println(p)
    println(p.first)
    println(p.second)

    val charPair = 'a' to 1
    println(charPair)

    val m = mapOf(1 to "one", 2 to "two")
    println(m[1])
    println(m[2])
    println(m.size)

    val mm = mutableMapOf('a' to 1)
    mm.put('b', 2)
    println(mm['a'])
    println(mm['b'])
    println(mapOf('a' to 1, 'b' to 2))

    val list = listOf(3 to "three", 4 to "four")
    println(list.size)
    println(list[0].second)

    val nested = (true to 1) to "ok"
    println(nested.first.first)
    println(nested.first.second)
    println(nested.second)
}
