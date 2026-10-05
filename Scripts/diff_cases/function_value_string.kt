fun top(): Int = 7
fun sum(x: Int, y: String?): Int = x + (y?.length ?: 0)
fun isFunctionDescription(text: String): Boolean = text.contains("@") || text.contains("->")

class Counter(val base: Int) {
    fun add(value: Int): Int = base + value
}

fun String.measure(): Int = length
fun lengths(values: List<Int>): Int = values.size

fun main() {
    val f = { 1 }
    val text = f.toString()
    println(isFunctionDescription(text))
    println(text == f.toString())
    println("$f" == text)
    println(listOf(f).toString() == "[$text]")
    val erased: Any = f
    println(erased.toString() == text)
    val captured = 8
    val closure = { captured + 1 }
    println(isFunctionDescription(closure.toString()))
    println(listOf(closure).toString() == "[${closure.toString()}]")
    println(closure())
    val anonymous = fun() = 2
    println(isFunctionDescription(anonymous.toString()))
    println(anonymous())
    val block = fun(): Int { return 3 }
    println(isFunctionDescription(block.toString()))
    println(block())
    println((fun(x: Int): Int = x + 1)(4))
    val capturedAnonymous = fun(x: Int) = captured + x
    println(isFunctionDescription(capturedAnonymous.toString()))
    println(capturedAnonymous(2))
    println(listOf(f)[0]())
    println(listOf(closure)[0]())
    val mutable = mutableListOf<() -> Int>()
    mutable.add(f)
    println(mutable.toString() == "[$text]")
    println(mapOf("fn" to f).toString() == "{fn=$text}")
    println(::top)
    println((::top).toString())
    println("${::top}")
    println(listOf(::top))
    println((::sum).toString())
    val counter = Counter(10)
    println((counter::add).toString())
    println((Counter::add).toString())
    println((String::measure).toString())
    println(("abc"::measure).toString())
    println((::lengths).toString())
    val nullable: (() -> Int)? = null
    println(nullable.toString())
    println(f())
}
