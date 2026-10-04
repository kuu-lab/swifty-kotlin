fun top(): Int = 7
fun sum(x: Int, y: String?): Int = x + (y?.length ?: 0)

fun main() {
    val f = { 1 }
    val text = f.toString()
    println(text.isNotEmpty() && text != "1")
    println(text == f.toString())
    println("$f" == text)
    println(listOf(f).toString() == "[$text]")
    val erased: Any = f
    println(erased.toString() == text)
    val captured = 8
    val closure = { captured + 1 }
    println(closure.toString().isNotEmpty())
    println(listOf(closure).toString() == "[${closure.toString()}]")
    println(closure())
    val anonymous = fun() = 2
    println(anonymous.toString().isNotEmpty())
    println(anonymous())
    val block = fun(): Int { return 3 }
    println(block.toString().isNotEmpty())
    println(block())
    println((fun(x: Int): Int = x + 1)(4))
    println(::top)
    println((::top).toString())
    println("${::top}")
    println(listOf(::top))
    println((::sum).toString())
    val nullable: (() -> Int)? = null
    println(nullable.toString())
    println(f())
}
