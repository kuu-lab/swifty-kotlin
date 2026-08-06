fun main() {
    val lock = object {}
    var counter = 0
    val result = synchronized(lock) {
        counter += 1
        val nested = synchronized(lock) { counter + 40 }
        nested + 1
    }
    println(result)
    println(counter)
    synchronized(lock) {
        println("unit block")
    }
    val text: String = synchronized(lock) { "hello" }
    println(text)
    try {
        synchronized(lock) { throw IllegalStateException("boom") }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
}
