package kotlinx.io
import kotlin.test.assertEquals
fun assertByteArrayEquals(expectedUtf8: String, b: ByteArray) {
    assertEquals(expectedUtf8, b.toString(Charsets.UTF_8))
}
