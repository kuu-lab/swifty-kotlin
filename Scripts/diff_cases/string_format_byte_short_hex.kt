fun main() {
    val b: Byte = -29
    val bm: Byte = -1
    val bp: Byte = 0x7f
    val sm: Short = -1
    val sn: Short = -30000
    val sp: Short = 0x7fff
    val im: Int = -29
    val lm: Long = -29L

    // JVM Formatter masks %x/%o to the boxed type's own width:
    // Byte -> 8 bits, Short -> 16 bits, Int -> 32 bits, Long -> 64 bits.
    println("%x".format(b))
    println("%02x".format(b))
    println("%04x".format(bm))
    println("%X".format(bm))
    println("%x".format(bp))
    println("%08x".format(bm))
    println("%5x".format(bm))
    println("%-8x|".format(bm))
    println("%#x".format(bm))
    println("%#o".format(bm))
    println("%x".format(Byte.MIN_VALUE))
    println("%o".format(Byte.MIN_VALUE))
    println("%o".format(bm))

    println("%x".format(sm))
    println("%02x".format(sn))
    println("%04x".format(sm))
    println("%X".format(sp))
    println("%08x".format(sm))
    println("%x".format(Short.MIN_VALUE))
    println("%o".format(sm))

    println("%x".format(im))
    println("%04x".format(im))
    println("%x".format(lm))
    println("%016x".format(-1L))
    println("%o".format(im))
    println("%o".format(lm))

    // %d keeps the signed value (no masking).
    println("%d".format(b))
    println("%d".format(bm))
    println("%d".format(sm))
    println("%05d".format(b))
    println("%(d".format(b))
    println("%d".format(200.toByte()))

    // Companion-object call form and argument indexing.
    println(String.format("%02x", bm))
    println("%1\$x %1\$x".format(bm))
    println("%2\$x %1\$x".format(bm, sm))
    println("%x %<X".format(bm))
    println("%02x %04x %08x %016x".format(bm, sm, im, -1L))
    println("%5.3s-%02x".format("abcdef", b))
}
