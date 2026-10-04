object Singleton {
    override fun toString(): String = "I am Singleton"
}

fun main() {
    val erased: Any = Singleton
    println(Singleton)
    print(Singleton)
    println()
    println(erased)
    println("prefix=$erased")
}
