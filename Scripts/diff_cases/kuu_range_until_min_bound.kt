fun main() {
    val r = 7 until Int.MIN_VALUE; println("${r.first} ${r.last} ${r.isEmpty()}")
    val u = 7u until 0u; println("${u.first} ${u.last} ${u.isEmpty()}")
    val l = 7L until Long.MIN_VALUE; println("${l.first} ${l.last}")
    val ul = 7uL until 0uL; println("${ul.first} ${ul.last} ${ul.isEmpty()}")
    val c = 'x' until '\u0000'; println("${c.first.code} ${c.last.code} ${c.isEmpty()}")
}
