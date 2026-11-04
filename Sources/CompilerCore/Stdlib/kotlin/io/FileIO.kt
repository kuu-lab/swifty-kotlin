package kotlin.io

import java.io.File
import java.nio.file.Files
import kotlin.internal.KsSymbolName
import kotlin.text.Charset
import kotlin.text.Charsets

// KSP-484: keep file-content access in the runtime, but move line iteration and
// its empty/trailing-line policy into bundled Kotlin source.

// The private boundary takes an Int CharsetTag. Source wrappers extract it
// from the public Charset object before invoking this unchanged ABI — the
// same convention CharsetStreams.kt uses (KUU-4077: previously the Charset
// object itself was passed, so every charset read silently decoded as UTF-8
// and non-UTF-8 content threw FileSystemException).
@KsSymbolName("__kk_file_readText")
private external fun __kkFileReadText(file: File, charsetTag: Int): String

public fun File.readText(): String =
    __kkFileReadText(this, Charsets.UTF_8.tag)

public fun File.readText(charset: Charset): String =
    __kkFileReadText(this, charset.tag)

// KUU-4077: `java.nio.file.Files.readAllBytes` already walks the
// `__kk_io_fs_*` descriptor bridges, so `readBytes` gets whole-file reads
// (and FileNotFoundException on open failure) without a new runtime entry.
public fun File.readBytes(): ByteArray =
    Files.readAllBytes(toPath())

@PublishedApi
internal fun fileLines(file: File): List<String> =
    fileLines(file, Charsets.UTF_8)

@PublishedApi
internal fun fileLines(file: File, charset: Charset): List<String> {
    val content = file.readText(charset)
    if (content.isEmpty()) return emptyList()

    // Match BufferedReader.readLine: LF, CR, and CRLF are all terminators
    // and are not included in the line. Collapse CRLF first so its CR is
    // not treated as a second break. A trailing terminator must not yield
    // an extra empty line (unlike String.lines()).
    val normalized = content.replace("\r\n", "\n").replace("\r", "\n")
    val lines = normalized.split("\n")
    if (lines.size > 0 && lines[lines.size - 1].isEmpty()) {
        return lines.subList(0, lines.size - 1)
    }
    return lines
}

public fun File.readLines(): List<String> = fileLines(this)

public fun File.readLines(charset: Charset): List<String> = fileLines(this, charset)

public inline fun File.forEachLine(action: (String) -> Unit) {
    for (line in fileLines(this)) {
        action(line)
    }
}

public inline fun File.forEachLine(charset: Charset, action: (String) -> Unit) {
    for (line in fileLines(this, charset)) {
        action(line)
    }
}

public inline fun <T> File.useLines(block: (List<String>) -> T): T = block(fileLines(this))

public inline fun <T> File.useLines(charset: Charset, block: (List<String>) -> T): T =
    block(fileLines(this, charset))
