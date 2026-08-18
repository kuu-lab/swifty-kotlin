@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package golden.sema

annotation class MyMarker

@OptIn(MyMarker::class)
fun useOptIn(): Int = 1
