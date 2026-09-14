fun <R> passThroughList(list: List<R>): List<R> {
    val result = mutableListOf<R>()
    for (item in list) {
        result.add(item)
    }
    return result
}

fun main() {
    val r: List<Char> = listOf("a", "bb").flatMap { it.toList() }
    println(r)

    val a = mutableListOf<Char>()
    a.add('a')
    a.add('b')
    val b = listOf('a', 'b')
    println(a == b)
    println(a.hashCode() == b.hashCode())
    println(a.hashCode())

    val s = mutableSetOf<Char>()
    s.add('a')
    s.add('a')
    s.add('b')
    println(s.size)
    println('a' in s)

    val m = mutableMapOf<Char, Int>()
    m['a'] = 1
    m['a'] = 2
    println(m)
    println(m['a'])

    println(a.toSet())
    println(a.indexOf('b'))
    println("aab".toList().distinct())

    val l: MutableList<Char?> = mutableListOf()
    l.add('a')
    l.add(null)
    println(l)
    println(l.filterNotNull())

    println(passThroughList(listOf('x', 'y')))
}
