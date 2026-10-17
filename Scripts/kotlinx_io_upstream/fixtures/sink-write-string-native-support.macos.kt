/*
 * Test-only Native support adapter for the selected Sink.writeString assertions.
 * The upstream tempFileName implementation reads an internal stdlib path and is
 * not needed by these six selected test bodies. Keep its actual declaration so
 * the common test support source resolves, and use macOS's /tmp directory here.
 */

package kotlinx.io

import kotlin.random.Random

actual fun tempFileName(): String = "/tmp/${Random.nextBytes(32).toHexString()}"

internal actual fun String.asUtf8ToByteArray(): ByteArray = commonAsUtf8ToByteArray()
