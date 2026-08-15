package kotlin.io

import java.io.File
import kotlin.internal.KsSymbolName

// KSP-484: keep file-content access in the runtime, but move line iteration and
// its empty/trailing-line policy into bundled Kotlin source.

@KsSymbolName("__kk_file_readText")
private external fun __kkFileReadText(file: File): String

private fun fileLines(file: File): List<String> {
    val content = __kkFileReadText(file)
    if (content.isEmpty()) return emptyList()

    val lines = content.split("\n")
    if (lines.size > 0 && lines[lines.size - 1].isEmpty()) {
        return lines.subList(0, lines.size - 1)
    }
    return lines
}

public fun File.readLines(): List<String> = fileLines(this)

public fun File.forEachLine(action: (String) -> Unit) {
    for (line in fileLines(this)) {
        action(line)
    }
}

public fun <T> File.useLines(block: (List<String>) -> T): T = block(fileLines(this))
