fun main() {
    val x by lazy {
        println("initializing x")
        42
    }
    println("before")
    println(x)
    println(x)

    val unused by lazy {
        println("must not initialize")
        0
    }

    val captured by lazy { 7 }
    val read = { captured }
    println(read())
}
