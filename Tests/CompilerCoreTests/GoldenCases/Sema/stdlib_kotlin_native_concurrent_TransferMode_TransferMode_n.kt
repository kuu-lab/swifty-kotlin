@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

package golden.sema

import kotlin.native.concurrent.TransferMode

fun transferModeEntries(): kotlin.enums.EnumEntries<TransferMode> = TransferMode.entries
fun transferModeValue(): Int = TransferMode.SAFE.value
fun transferModeValueOf(): TransferMode = TransferMode.valueOf("UNSAFE")
fun transferModeValues(): Array<TransferMode> = TransferMode.values()
