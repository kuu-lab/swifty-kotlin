// DIFF_JVM
open class Base {
    protected open fun value(): Int = 1
    protected open val label: Int get() = 1

    fun callValue(): Int = value()
    fun callLabel(): Int = label
}

class Holder {
    val adapter = object : Base() {
        protected override fun value(): Int = 2
        protected override val label: Int get() = 2
    }
}

fun main() {
    val holder = Holder()
    println(holder.adapter.callValue())
    println(holder.adapter.callLabel())
}
