@file:OptIn(kotlin.ExperimentalMultiplatform::class)

import kotlin.experimental.ExpectRefinement

fun main() {
    val marker: ExpectRefinement? = null
    println(marker == null)
}
