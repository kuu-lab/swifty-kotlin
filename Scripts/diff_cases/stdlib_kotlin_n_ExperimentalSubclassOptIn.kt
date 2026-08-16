@file:OptIn(ExperimentalSubclassOptIn::class)

import kotlin.ExperimentalSubclassOptIn

@ExperimentalSubclassOptIn
annotation class MyExperimentalMarker

@MyExperimentalMarker
class AnnotatedClass

fun main() {
    println("ok")
}
