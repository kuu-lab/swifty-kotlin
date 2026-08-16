@file:OptIn(ExperimentalSubclassOptIn::class)
package golden.sema

import kotlin.ExperimentalSubclassOptIn

@ExperimentalSubclassOptIn
annotation class MyExperimentalMarker

@MyExperimentalMarker
class AnnotatedClass

fun useMarker(): String = "ok"
