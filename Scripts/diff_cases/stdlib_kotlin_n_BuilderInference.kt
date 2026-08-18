@file:OptIn(kotlin.experimental.ExperimentalTypeInference::class)

@kotlin.BuilderInference
fun buildFunction(): Int = 0

@kotlin.BuilderInference
val buildProperty: Int = 0

fun main() {
    println("stdlib_kotlin_n_BuilderInference ok")
}
