import kotlin.OverloadResolutionByLambdaReturnType
import kotlin.experimental.ExperimentalTypeInference

@OptIn(ExperimentalTypeInference::class)
fun main() {
    val marker = OverloadResolutionByLambdaReturnType()
    println(marker is OverloadResolutionByLambdaReturnType)
}
