// Regression: inside a generic class/interface, `this` used from a property
// accessor must be typed as `C<T>` (not the raw nominal), otherwise generic
// calls taking `C<T>` fail to resolve.
class Box<T> {
    val sizeViaAccessor: Int
        get() = sizeOf(this)

    fun sizeViaFun(): Int = sizeOf(this)
}

fun <T> sizeOf(box: Box<T>): Int = 42

interface Named<T> {
    val label: String
        get() = describe(this)
}

fun <T> describe(named: Named<T>): String = "named"

class Impl : Named<Int>

fun main() {
    val box = Box<Int>()
    println(box.sizeViaFun())
    println(box.sizeViaAccessor)
    println(Impl().label)
}
