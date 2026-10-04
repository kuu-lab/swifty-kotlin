// BUG-147: local `by lazy` used to bind the local to the Lazy handle itself.
fun main() {
    val x by lazy { 42 }
    println(x)
    println(x + 1)

    val s by lazy {
        println("initializing")
        "hello"
    }
    println(s)
    println(s.length)
}
