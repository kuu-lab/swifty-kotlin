class DefaultOuter(val seed: Int) {
    inner class Inner(val first: Int = seed + 7, val second: Int = first + seed) {
        fun describe() = "$first/$second/$seed"
    }

    fun makeInner() = Inner()
}

fun main() {
    val outer = DefaultOuter(10)
    println(outer.Inner().describe())
    println(outer.Inner(4).describe())
    println(outer.Inner(second = 99).describe())
    println(outer.Inner(2, 3).describe())
    println(outer.makeInner().describe())

    val present: DefaultOuter? = DefaultOuter(20)
    println(present?.Inner()?.describe())
    val absent: DefaultOuter? = null
    println(absent?.Inner()?.describe())
}
