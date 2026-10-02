data class D(val id: Int) { var note = 0 }

fun main() {
    val a = D(1).apply { note = 1 }
    val b = D(1).apply { note = 2 }
    println(a == b)
    println(setOf(a, b).size)
    println(listOf(a).indexOf(b))
    println(mutableMapOf(a to "x")[b])
    println(a.hashCode() == b.hashCode())
    println(a)
    println(a.copy().note)
}
