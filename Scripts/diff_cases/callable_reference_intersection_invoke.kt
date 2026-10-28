// KOTLINC_FLAGS: -Xjdk-release=17
fun render(value: Boolean): String = value.toString()
fun applyOp(op: (Int) -> Int): Int = op(1)

fun main() {
    val reference: (Boolean) -> Any = ::render
    val reflected = reference as kotlin.reflect.KFunction<*>
    println(reference(true))
    println(reflected.name)

    val higherOrder: ((Int) -> Int) -> Int = ::applyOp
    val higherReflected = higherOrder as kotlin.reflect.KFunction<*>
    println(higherOrder { it + 1 })
    println(higherReflected.name)
}
