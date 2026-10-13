@file:Suppress("DEPRECATION_ERROR")

import kotlinx.io.files.*
import kotlinx.io.writeString
import kotlinx.io.readString
import kotlin.random.Random

// Uses the restored actual legacy extensions; expected one line "legacy".
fun main() {
    val path = Path(SystemTemporaryDirectory, "kswiftk-b06-legacy-" + Random.nextInt(1, 1000000000))
    try {
        path.sink().use { it.writeString("legacy") }
        path.source().use { println(it.readString()) }
    } finally {
        SystemFileSystem.delete(path, mustExist = false)
    }
}
