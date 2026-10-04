fun returnUnit(): Unit = Unit

fun main() {
    val direct: Unit = Unit
    val erased: Any = direct
    println(direct.toString())
    println(erased.toString())
    println("$direct")
    println(direct)
    println(returnUnit().toString())
    println(Unit === Unit)
    println(returnUnit() === Unit)
    println(returnUnit() is Unit)

    val first: Any = Unit
    val second: Any = Unit
    println(first === second)
    println(first == second)
    println(first.toString())
}
