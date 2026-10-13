fun f() { }
fun explicitUnit(): Unit = Unit
fun <T> identity(value: T): T = value

fun main() {
    val u = Unit
    println(u == Unit)
    println(f() == Unit)
    println(f() === Unit)
    println(run { } == Unit)
    println(listOf(1).forEach { } == Unit)
    println(run { 1; Unit } === Unit)
    println(when (f()) { Unit -> "w"; else -> "e" })
    val x: Any = f()
    println(x is Unit)
    println(x === Unit)
    println(explicitUnit() === Unit)
    val block: () -> Unit = { }
    println(block() === Unit)
    println(identity(f()) === identity(Unit))
    println(kotlin.Unit === f())
    val nullable: Any? = f()
    println(nullable === Unit)
    val absent: Any? = null
    println(absent === Unit)
    println(x == 0)
    println(f() != Unit)
    println(f() !== Unit)
    println(Unit === x)
    println(when (x) { Unit -> "boxed"; else -> "other" })
    println(Unit.toString())
}
