package kotlin

import kotlin.internal.KsSymbolName

// KSP-786: source-backed declaration for the primitive short array factory.
// The shared array factory lowering packs the vararg elements before calling
// the runtime's common kk_array_of entry point.
@KsSymbolName("kk_array_of")
public external fun shortArrayOf(vararg elements: Short): ShortArray
