fun main() {
    val star = "🌟"
    println(star.first())
    println("hello🌟".lastOrNull())
    val boxed: Any = star.last()
    println(boxed)
    println(star.last().toString().first().code)
    println("x" + star.last() + "y")
    println(star)
    println("�")
    print(star.last())
    println("!")
}
