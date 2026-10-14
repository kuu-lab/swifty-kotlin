// KUU-2046: expression annotations preserve operand and control-flow semantics.
class Bag {
    fun add(x: Int): Int = x
    fun adding(x: Int): Int = @Suppress("DEPRECATION") add(x)
    fun control(x: Int): Int = add(x)
}

fun choose(flag: Boolean): Int = when {
    flag -> @Suppress("UNUSED_VARIABLE") {
        val value = 7
        value
    }
    else -> 9
}

fun controlChoose(flag: Boolean): Int = when {
    flag -> {
        val value = 7
        value
    }
    else -> 9
}

fun throwing(): Int = @Suppress("UNUSED") throw IllegalArgumentException("annotated")
fun unary(): Int = @kotlin.Suppress("UNUSED") -7 + 9
fun annotatedIf(flag: Boolean): Int = if (flag) @Suppress("UNUSED") { 3 } else @Suppress("UNUSED") { 4 }
fun invokedBranch(flag: Boolean): Int = when {
    flag -> @Suppress("UNUSED") ({ x: Int -> x + 1 })(2)
    else -> ({ x: Int -> x - 1 })(2)
}

fun main() {
    println(Bag().adding(13))
    println(Bag().control(13))
    println(choose(true))
    println(choose(false))
    println(controlChoose(true))
    println(controlChoose(false))
    println(unary())
    println(annotatedIf(true))
    println(annotatedIf(false))
    println(invokedBranch(true))
    println(invokedBranch(false))
    var value = 1
    println(++@Suppress("UNUSED") value)
    println(@Suppress("UNUSED") ++value)
    println(-@Suppress("UNUSED") value)
    println(@Suppress("UNUSED") listOf(5, 6)[1])
    println(@Suppress("UNUSED") Bag().adding(4))
    val nullable: String? = "suffix"
    println(@Suppress("UNUSED") nullable!!.length)
    try {
        throwing()
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
}
