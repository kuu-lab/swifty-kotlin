// KUU-1155: signed small integers must sign-extend before truncating to UShort.
fun Byte.implicitUShort(): UShort = toUShort()
fun Short.implicitUShort(): UShort = toUShort()
fun Byte.explicitThisUShort(): UShort = this.toUShort()
fun Short.explicitThisUShort(): UShort = this.toUShort()
fun byteUShort(value: Byte): UShort = value.toUShort()
fun shortUShort(value: Short): UShort = value.toUShort()
fun nullableByteUShort(value: Byte?): UShort? = value?.toUShort()
fun nullableShortUShort(value: Short?): UShort? = value?.toUShort()

fun main() {
    println((-1).toByte().toUShort())
    println(0x55.toByte().toUShort())
    println((-1).toShort().toUShort())

    for (value in -128..127) {
        val byte = value.toByte()
        println(byteUShort(byte))
        println(byte.implicitUShort())
        println(byte.explicitThisUShort())
        println(nullableByteUShort(byte))
    }
    for (value in listOf(-32768, -32767, -256, -129, -128, -1, 0, 1, 85, 127, 128, 255, 256, 32766, 32767)) {
        val short = value.toShort()
        println(shortUShort(short))
        println(short.implicitUShort())
        println(short.explicitThisUShort())
        println(nullableShortUShort(short))
    }
    println(nullableByteUShort(null))
    println(nullableShortUShort(null))
}
