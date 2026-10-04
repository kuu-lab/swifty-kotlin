@file:OptIn(kotlin.experimental.ExperimentalTypeInference::class)

package golden.sema

@kotlin.BuilderInference
fun buildFunction(): Int = 0

@kotlin.BuilderInference
val buildProperty: Int = 0

fun useBuilderInference(): kotlin.BuilderInference? = null
