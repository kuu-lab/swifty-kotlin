fun main() {
    val t1 = Throwable()
    val t2 = Throwable("hello")
    val t3 = Throwable("nested", t1)
    println("created")
    println(t2.message ?: "ok2")
    println(t3.message ?: "ok3")

    try {
        throw Throwable("boom")
    } catch (e: Throwable) {
        println("caught: ${e.message}")
    }
}
