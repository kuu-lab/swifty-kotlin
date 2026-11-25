// DIFF_JVM
// Explicit kotlin.jvm annotation imports must resolve for JVM consumers;
// paging-common commonMain imports JvmSynthetic/JvmOverloads/JvmStatic this way.
import kotlin.jvm.JvmOverloads
import kotlin.jvm.JvmStatic
import kotlin.jvm.JvmSynthetic

class Holder {
    companion object {
        @JvmStatic
        @JvmSynthetic
        fun visible(x: Int = 1): Int = x
    }

    @JvmOverloads
    fun overloaded(a: Int = 1, b: Int = 2): Int = a + b
}

fun main() {
    println(Holder.visible())
    println(Holder.visible(4))
    val holder = Holder()
    println(holder.overloaded())
    println(holder.overloaded(5))
    println(holder.overloaded(5, 6))
}
