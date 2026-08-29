@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

package golden.sema

import kotlin.native.concurrent.FutureState

fun futureStateEntries(): kotlin.enums.EnumEntries<FutureState> = FutureState.entries
fun futureStateValue(): Int = FutureState.COMPUTED.value
fun futureStateValueOf(): FutureState = FutureState.valueOf("THROWN")
fun futureStateValues(): Array<FutureState> = FutureState.values()
