fun main() {
    val m = mutableMapOf<Any, String>()
    m['a'] = "char"
    m[97] = "int"
    println(m.size)
    println(m['a'])
    println(m[97])
    val s = mutableSetOf<Any>()
    s.add('A')
    println(s.add(65))
    println(s.contains(65L))
    println(s.contains('A'))
    println(s.size)
}
