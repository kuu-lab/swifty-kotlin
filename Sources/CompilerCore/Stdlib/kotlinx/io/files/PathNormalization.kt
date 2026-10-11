/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 * Derived from pinned kotlinx-io 0.9.1 core/common/src/files/Paths.kt.
 */
package kotlinx.io.files

import kotlinx.io.isWindows

internal fun removeTrailingSeparators(path: String, /* only for testing */ isWindows_: Boolean = isWindows): String {
    if (isWindows_) {
        // don't trim the path separator right after the drive name
        val limit = if (path.length > 1) {
            if (path[1] == ':') {
                3
            } else if (isUnc(path)) {
                2
            } else {
                1
            }
        } else {
            1
        }
        return removeTrailingSeparatorsWindows(limit, path)
    }
    return removeTrailingSeparatorsUnix(path)
}

private fun isUnc(path: String): Boolean {
    if (path.length < 2) return false
    if (path.startsWith("$WindowsPathSeparator$WindowsPathSeparator")) return true
    if (path.startsWith("$UnixPathSeparator$UnixPathSeparator")) return true
    return false
}

private fun removeTrailingSeparatorsUnix(path: String): String {
    var idx = path.length
    while (idx > 1 && path[idx - 1] == UnixPathSeparator) {
        idx--
    }
    return path.substring(0, idx)
}

private fun removeTrailingSeparatorsWindows(suffixLength: Int, path: String): String {
    require(suffixLength >= 1)
    var idx = path.length
    while (idx > suffixLength) {
        val c = path[idx - 1]
        if (c != WindowsPathSeparator && c != UnixPathSeparator) break
        idx--
    }
    return path.substring(0, idx)
}

internal const val WindowsPathSeparator: Char = '\\'
internal const val UnixPathSeparator: Char = '/'
