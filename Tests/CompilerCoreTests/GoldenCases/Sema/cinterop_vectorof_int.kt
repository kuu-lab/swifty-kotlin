package golden.sema

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.Vector128
import kotlinx.cinterop.vectorOf

@ExperimentalForeignApi
fun makeIntVector(): Vector128 = vectorOf(1, 2, 3, 4)
