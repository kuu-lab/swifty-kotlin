// KSP-1192: Byte/Short/UShort receivers of toUByte() type-checked but had no
// entry in the CallLowerer conversion tables, so codegen emitted a bare
// `toUByte` symbol that failed at link time. Pins kk_byte_to_ubyte,
// kk_short_to_ubyte and the (previously unreferenced) kk_ushort_to_ubyte case.
@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    println((-1).toByte().toUByte())
    println(Byte.MIN_VALUE.toUByte())
    println(127.toByte().toUByte())
    println((-2).toShort().toUByte())
    println(256.toShort().toUByte())
    println(Short.MIN_VALUE.toUByte())
    println(60000.toUShort().toUByte())
    println(200.toUByte().toUByte())
}
