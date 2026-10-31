// KUU-3818: an `inline` member function reached through virtual dispatch is
// never inlined, so a capturing lambda argument must be materialized to the
// boxed function-value ABI. Passing the raw lambda symbol across the vtable
// boundary crashed (SIGBUS) inside `kk_function_invoke`.

open class Box {
    inline protected fun <T> applyProtected(arg: T, func: (T) -> T): T = func(arg)
    inline fun <T> applyPublic(arg: T, func: (T) -> T): T = func(arg)
    inline fun applyNonGeneric(arg: Int, func: (Int) -> Int): Int = func(arg)
    inline fun applyDefault(arg: Int = 5, func: (Int) -> Int): Int = func(arg)
    fun viaThis(x: Int, y: Int): Int = this.applyPublic(x) { it * y }
    fun viaImplicit(x: Int, y: Int): Int = applyProtected(x) { it * y }
    fun viaOther(other: Box, x: Int, y: Int): Int = other.applyProtected(x) { it * y }
    fun viaNonGeneric(other: Box, x: Int, y: Int): Int = other.applyNonGeneric(x) { it * y }
    fun viaDefault(x: Int, y: Int): Int = applyDefault(x) { it + y }
}

class FinalBox {
    inline fun applyFinal(arg: Int, func: (Int) -> Int): Int = func(arg)
}

fun viaParameter(b: Box, x: Int, y: Int): Int = b.applyPublic(x) { it * y }
fun viaNullable(b: Box?, x: Int, y: Int): Int = b?.applyPublic(x) { it * y } ?: -1

fun main() {
    val b = Box()
    println(b.viaThis(2, 3))
    println(b.viaImplicit(2, 3))
    println(b.viaOther(Box(), 5, 4))
    println(b.viaNonGeneric(Box(), 2, 3))
    println(b.viaDefault(2, 3))
    println(FinalBox().applyFinal(7) { it + 1 })
    println(viaParameter(Box(), 2, 3))
    println(viaNullable(Box(), 5, 4))
    println(viaNullable(null, 5, 4))
}
