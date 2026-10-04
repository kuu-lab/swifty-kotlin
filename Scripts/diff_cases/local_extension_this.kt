fun Int.outerReceiver(): Int {
    val bonus = 10
    fun Int.combine(extra: Int = 1): Int = this + this@outerReceiver + bonus + extra
    return 3.combine()
}

fun main() {
    fun Int.twice(): Int = this * 2
    println(3.twice())

    fun Int.out(): Int = this + 1
    println(7.out())

    fun String.decorate(): String { return this + "!" }
    println("ok".decorate())

    val offset = 10
    fun Int.add(extra: Int): Int = offset + this + extra
    println(3.add(4))
    val present: Int? = 5
    val absent: Int? = null
    println(present?.add(2))
    println(absent?.add(2))

    fun Int?.orZero(): Int = this ?: 0
    println(present.orZero())
    println(absent.orZero())

    println(20.outerReceiver())

    fun Int.nested(): Int {
        fun read(): Int = this
        return read()
    }
    println(7.nested())

    fun Int.inLambda(): Int = with("abc") { this.length + this@inLambda }
    println(4.inLambda())

    fun Int.recursive(): Int = if (this == 0) offset else (this - 1).recursive() + 1
    println(3.recursive())

    fun regular(n: Int): Int = n + 1
    println(regular(8))
}
