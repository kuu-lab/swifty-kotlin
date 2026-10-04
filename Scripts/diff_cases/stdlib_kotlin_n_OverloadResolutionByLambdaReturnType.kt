import kotlin.OptIn
import kotlin.OverloadResolutionByLambdaReturnType
import kotlin.experimental.ExperimentalTypeInference

@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
fun foo(block: () -> Int): Int = 1

fun foo(block: () -> String): String = "s"

fun main() {
    println(foo { 42 })
    println(foo { "hello" })
}
