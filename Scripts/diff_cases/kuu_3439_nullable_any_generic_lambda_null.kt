// KUU-3439: reading the nullable Any? payload from a value class returned via
// a generic lambda must compare the payload with null without reboxing the class.
@JvmInline
value class X(val x: Any?)

fun useX(x: X): String = if (x.x == null) "OK" else "fail: $x"
fun <T> call(fn: () -> T) = fn()

fun main() {
    println(useX(call { X(null) }))
}
