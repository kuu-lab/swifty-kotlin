package f02constructornegative

import kotlinx.io.bytestring.ByteString

fun main() {
    // This call would only resolve through the private primary constructor.
    ByteString(byteArrayOf(1), true)
}
