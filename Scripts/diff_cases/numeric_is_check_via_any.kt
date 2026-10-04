fun main() {
    val i: Any = 42
    println(i is Int)
    println(i is Long)

    val l: Any = 42L
    println(l is Long)
    println(l is Int)

    when (i) {
        is Long -> println("long")
        is Int -> println("int")
        else -> println("other")
    }

    println(i as? Long)
    println(i as? Int)

    try {
        println(i as Long)
    } catch (e: ClassCastException) {
        println("caught")
    }
}
