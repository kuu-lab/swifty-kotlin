package golden.sema

import kotlin.OptIn
import kotlin.OverloadResolutionByLambdaReturnType
import kotlin.experimental.ExperimentalTypeInference

@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
fun foo(block: () -> Int): Int = 1

fun foo(block: () -> String): String = "s"

fun test(): Int = foo { 42 }
