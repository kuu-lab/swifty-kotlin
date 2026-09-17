package kuu560

val computedAnswer: Int get() = 42

class Holder {
    companion object {
        val answer: Int get() = 7
    }
}

fun main() {
    println(kotlin.math.PI)
    println(kotlin.math.E)
    println(kotlin.Int.MAX_VALUE)
    println(kotlin.Int.MIN_VALUE)
    println(kotlin.Int.Companion.MAX_VALUE)
    println(kuu560.computedAnswer)
    println(kuu560.Holder.answer)
    println(kuu560.Holder.Companion.answer)
    println(kotlin.math.abs(-1))
}
