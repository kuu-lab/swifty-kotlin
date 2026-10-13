@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package kotlinx.io
import kotlinx.io.files.SystemTemporaryDirectory
import platform.posix.F_OK
import platform.posix.access
import kotlin.random.Random
fun tempFileName(): String {
    val tmpDir = SystemTemporaryDirectory.path
    for (i in 0 until 10) {
        val name = Random.nextBytes(32).toHexString()
        val path = "$tmpDir/$name"
        if (access(path, F_OK) != 0) {
            return path
        }
    }
    throw IOException("Failed to generate temp file name")
}
