package kotlin.io

import java.io.File
import kotlin.jvm.internal.__jvmFileName

private fun fileRootLength(path: String): Int {
    var first = path.indexOf('/', 0)
    if (first == 0) {
        if (path.length > 1 && path[1] == '/') {
            first = path.indexOf('/', 2)
            if (first >= 0) {
                first = path.indexOf('/', first + 1)
                if (first >= 0) {
                    return first + 1
                }
                return path.length
            }
        }
        return 1
    }
    if (first > 0 && path[first - 1] == ':') {
        first++
        return first
    }
    if (first == -1 && path.endsWith(':')) {
        return path.length
    }
    return 0
}

private fun File.isRootedPath(): Boolean = fileRootLength(getPath()) > 0

public val File.extension: String
    get() = __jvmFileName(this).substringAfterLast('.', "")

public fun File.resolve(relative: File): File {
    if (relative.isRootedPath()) {
        return relative
    }
    val baseName = getPath()
    val relativeName = relative.getPath()
    return if (baseName.isEmpty() || baseName.endsWith('/')) {
        File(baseName + relativeName)
    } else {
        File(baseName + "/" + relativeName)
    }
}

public fun File.resolve(relative: String): File = resolve(File(relative))
