package kotlin.io

import java.io.File
import kotlin.jvm.internal.__jvmFileName
import kotlin.jvm.internal.__jvmFileSeparatorChar

public val File.extension: String
    get() = __jvmFileName(this).substringAfterLast('.', "")

public fun File.resolve(relative: String): File {
    val child = File(relative)
    val childPath = child.path
    val separator = __jvmFileSeparatorChar()
    val firstSeparator = childPath.indexOf(separator, 0, false)
    // Kotlin also treats a drive prefix ending in ':' as rooted.
    val rooted = when {
        firstSeparator == 0 -> true
        firstSeparator > 0 -> childPath[firstSeparator - 1] == ':'
        else -> childPath.endsWith(':')
    }
    if (rooted) return child

    val base = toString()
    val prefix = if (base.isEmpty() || base.endsWith(separator)) base else base + separator
    return File(prefix + childPath)
}
