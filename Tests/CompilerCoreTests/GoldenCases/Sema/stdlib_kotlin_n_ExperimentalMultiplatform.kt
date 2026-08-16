@file:OptIn(kotlin.ExperimentalMultiplatform::class)

package golden.sema

@ExperimentalMultiplatform
@Target(AnnotationTarget.FUNCTION)
annotation class MyExperimentalApi

@MyExperimentalApi
fun markedFun(): Int = 1
