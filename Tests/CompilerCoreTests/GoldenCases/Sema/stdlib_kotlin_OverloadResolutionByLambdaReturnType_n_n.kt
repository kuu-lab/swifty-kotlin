package golden.sema

import kotlin.OverloadResolutionByLambdaReturnType
import kotlin.experimental.ExperimentalTypeInference

@OptIn(ExperimentalTypeInference::class)
fun createMarker(): OverloadResolutionByLambdaReturnType = OverloadResolutionByLambdaReturnType()
