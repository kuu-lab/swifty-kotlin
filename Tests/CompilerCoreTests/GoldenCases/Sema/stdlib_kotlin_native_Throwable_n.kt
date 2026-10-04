@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package golden.sema

import kotlin.native.getStackTraceAddresses

fun probe(throwable: Throwable): List<Long> = throwable.getStackTraceAddresses()
