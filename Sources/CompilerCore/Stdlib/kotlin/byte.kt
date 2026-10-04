package kotlin

import kotlin.internal.KsSymbolName

// KSP-770: source-backed declaration for the primitive byte array factory.
// The shared array factory lowering packs the vararg elements before calling
// the runtime's common kk_array_of entry point.
@KsSymbolName("kk_array_of")
public external fun byteArrayOf(vararg elements: Byte): ByteArray
