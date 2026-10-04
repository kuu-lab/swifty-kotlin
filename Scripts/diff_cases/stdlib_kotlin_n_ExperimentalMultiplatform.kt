@file:OptIn(kotlin.ExperimentalMultiplatform::class)

@ExperimentalMultiplatform
@Target(AnnotationTarget.FUNCTION)
annotation class MyExperimentalApi

@MyExperimentalApi
fun markedFun(): Int = 42

fun main() {
    println("OK")
}
