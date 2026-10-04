package kotlin

import kotlin.internal.KsSymbolName

// KSP-769: Keep BooleanArray factory resolution source-backed while using the
// shared raw primitive-array vararg lowering and kk_array_of runtime entry point.
@KsSymbolName("kk_array_of")
public external fun booleanArrayOf(vararg elements: Boolean): BooleanArray
