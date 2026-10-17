package kotlinx.io

import kotlin.test.assertEquals

// This is the exact helper body from pinned core/common/test/util.kt.
fun assertArrayEquals(a: ByteArray, b: ByteArray) {
    assertEquals(a.contentToString(), b.contentToString())
}
