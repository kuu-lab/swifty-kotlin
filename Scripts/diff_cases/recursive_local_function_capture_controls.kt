import kotlin.reflect.KProperty

fun plain(): Int {
    fun factorial(n: Int): Int = if (n <= 1) 1 else n * factorial(n - 1)
    return factorial(5)
}

fun mutableCapture(): Int {
    var count = 0
    fun walk(n: Int) {
        count++
        if (n > 0) walk(n - 1)
    }
    walk(5)
    return count
}

class MemberCapture(private val base: Int) {
    fun run(): Int {
        fun walk(n: Int): Int = if (n == 0) base else walk(n - 1) + 1
        return walk(3)
    }
}

fun invokeStep(n: Int, action: (Int) -> Int): Int = action(n)

fun nestedLambdaCapture(): Int {
    var count = 0
    val base = 10
    fun walk(n: Int): Int {
        count++
        if (n == 0) return base + count
        return invokeStep(n - 1) { next -> invokeStep(next) { walk(it) } }
    }
    return walk(2)
}

class CapturedDelegate(private val value: Int) {
    operator fun getValue(receiver: Any?, property: KProperty<*>): Int = value
}

fun delegatedCapture(): Int {
    val value by CapturedDelegate(7)
    fun walk(n: Int): Int {
        if (n == 0) return value
        return invokeStep(n - 1) { walk(it) }
    }
    return walk(2)
}

fun boxedFunctionCapture(): Int {
    val value = 7
    val first = { value }
    val second = { first() }
    return second()
}

fun main() {
    println(plain())
    println(mutableCapture())
    println(MemberCapture(13).run())
    println(nestedLambdaCapture())
    println(delegatedCapture())
    println(boxedFunctionCapture())
}
