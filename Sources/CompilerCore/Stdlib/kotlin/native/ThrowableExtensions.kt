package kotlin.native

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_native_getStackTraceAddresses")
@kotlin.experimental.ExperimentalNativeApi
public external fun Throwable.getStackTraceAddresses(): List<Long>
