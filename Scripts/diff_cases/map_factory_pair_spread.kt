// KUU-1323: Spread arrays must retain both type arguments of user-class pairs.
class Desc(val number: Int?, val fullName: String)

fun f(): String? {
    val usage = linkedMapOf(*arrayOf(Desc(null, "x") to 0))
    return usage.iterator().next().key.fullName
}

fun main() {
    println(f())
    val descs = listOf(Desc(null, "x"), Desc(2, "y"))
    val usage = linkedMapOf(*descs.map { it to 0 }.toTypedArray())
    for ((d, n) in usage) {
        println(d.fullName)
        println(d.number)
        println(n + 1)
    }
    val pairs: Array<out Pair<Desc, Int>> = arrayOf(Desc(null, "middle") to 2)
    val mixed = linkedMapOf(Desc(1, "first") to 1, *pairs, Desc(3, "last") to 3)
    for ((d, n) in mixed) {
        println(d.fullName)
        println(n + 1)
    }
    println(mutableMapOf(*pairs).iterator().next().key.fullName)
    println(hashMapOf(*pairs).iterator().next().value + 1)
    println(mapOf(*pairs).iterator().next().key.fullName)
}
