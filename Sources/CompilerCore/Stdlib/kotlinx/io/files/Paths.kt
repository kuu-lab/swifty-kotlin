/*
 * Copyright 2017-2024 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/common/src/files/Paths.kt and
 * core/native/src/files/PathsNative.kt (POSIX representation).
 */
package kotlinx.io.files

import kotlin.internal.KsSymbolName

/** A string path in the host's POSIX filesystem. */
public class Path internal constructor(internal val path: String, @Suppress("UNUSED_PARAMETER") marker: Boolean) {
    // This compiler mis-types block-bodied getters at call sites, so the
    // bodies delegate to private member functions; call sites see the same
    // property signatures.
    public val parent: Path?
        get() = computeParent()

    private fun computeParent(): Path? {
        if (path.isEmpty() || path == "/" || !path.contains('/')) return null
        val prefix = path.substringBeforeLast('/')
        return Path(if (prefix.isEmpty()) "/" else prefix)
    }

    public val name: String
        get() = if (path.isEmpty() || path == "/") "" else path.substringAfterLast('/')

    public val isAbsolute: Boolean
        get() = path.startsWith('/')

    public val isRooted: Boolean
        get() = isAbsolute

    public val segments: List<String>
        get() = computeSegments()

    private fun computeSegments(): List<String> {
        val result = mutableListOf<String>()
        for (part in path.split("/")) {
            if (part.isNotEmpty()) result.add(part)
        }
        return result
    }

    override fun toString(): String = path
    override fun hashCode(): Int = path.hashCode()
    override fun equals(other: Any?): Boolean = other is Path && path == other.path
}

/** Returns `true` when this path refers to the filesystem root. */
public val Path.isRoot: Boolean
    get() = isAbsolute && segments.isEmpty()

/** Returns `true` when this path is not absolute. */
public val Path.isRelative: Boolean
    get() = !isAbsolute

private fun pathLastIndexOfChar(value: String, char: Char): Int =
    if (value.isEmpty()) -1 else value.lastIndexOf(char, value.length - 1, false)

/** Returns the last path segment without its file extension. */
public val Path.nameWithoutExtension: String
    get() {
        val pathName = this.name
        val dotIndex = pathLastIndexOfChar(pathName, '.')
        return if (dotIndex < 0) pathName else pathName.substring(0, dotIndex)
    }

private fun pathComponents(path: Path): List<String> =
    path.toString().split("/").filter { it.isNotEmpty() }

private fun normalizePathString(path: String): String {
    val absolute = path.startsWith("/")
    val stack = mutableListOf<String>()
    for (part in path.split("/")) {
        if (part.isEmpty() || part == ".") continue
        if (part == "..") {
            if (stack.isNotEmpty()) {
                if (stack.last() != "..") {
                    stack.removeAt(stack.size - 1)
                } else if (!absolute) {
                    stack.add(part)
                }
            } else if (!absolute) {
                stack.add(part)
            }
        } else {
            stack.add(part)
        }
    }
    val joined = stack.joinToString("/")
    return if (absolute) "/$joined" else if (joined.isEmpty()) "." else joined
}

/** Removes `.` segments and resolves `..` segments where possible. */
public fun Path.normalize(): Path = Path(normalizePathString(toString()))

/** Returns this path relative to [base], treating [base] as a directory. */
public fun Path.relativeTo(base: Path): Path {
    if (isAbsolute != base.isAbsolute) {
        throw IllegalArgumentException("this and base paths have different roots: $this and $base.")
    }

    val targetSegments = pathComponents(normalize())
    val baseSegments = pathComponents(base.normalize())
    var commonCount = 0
    val maxCommon = minOf(targetSegments.size, baseSegments.size)
    while (commonCount < maxCommon) {
        if (targetSegments[commonCount] != baseSegments[commonCount]) break
        commonCount++
    }

    val result = mutableListOf<String>()
    repeat(baseSegments.size - commonCount) { result.add("..") }
    if (commonCount < targetSegments.size) {
        result.addAll(targetSegments.subList(commonCount, targetSegments.size))
    }
    return Path(result.joinToString("/"))
}

/** Tests whether this path starts with all segments of [other]. */
public fun Path.startsWith(other: Path): Boolean {
    if (isAbsolute != other.isAbsolute) return false
    val pathSegments = pathComponents(this)
    val otherSegments = pathComponents(other)
    if (otherSegments.size > pathSegments.size) return false
    for (index in otherSegments.indices) {
        if (pathSegments[index] != otherSegments[index]) return false
    }
    return true
}

/** Tests whether this path starts with all segments of [other]. */
public fun Path.startsWith(other: String): Boolean = startsWith(Path(other))

/** Tests whether this path ends with all segments of [other]. */
public fun Path.endsWith(other: Path): Boolean {
    if (other.isAbsolute) return this == other
    val pathSegments = pathComponents(this)
    val otherSegments = pathComponents(other)
    if (otherSegments.size > pathSegments.size) return false
    val offset = pathSegments.size - otherSegments.size
    for (index in otherSegments.indices) {
        if (pathSegments[offset + index] != otherSegments[index]) return false
    }
    return true
}

/** Tests whether this path ends with all segments of [other]. */
public fun Path.endsWith(other: String): Boolean = endsWith(Path(other))

/** Resolves [relative] against this path, treating this path as a directory. */
public fun Path.resolve(relative: Path): Path {
    if (relative.isRooted) return relative
    val baseName = toString()
    val relativeName = relative.toString()
    return Path(if (baseName.isEmpty() || baseName.endsWith('/')) {
        baseName + relativeName
    } else {
        "$baseName/$relativeName"
    })
}

/** Resolves [relative] against this path, treating this path as a directory. */
public fun Path.resolve(relative: String): Path = resolve(Path(relative))

/** Resolves [relative] against this path. */
public operator fun Path.div(relative: Path): Path = resolve(relative)

/** Resolves [relative] against this path. */
public operator fun Path.div(relative: String): Path = resolve(relative)

/** The native POSIX path separator. */
public val SystemPathSeparator: Char get() = '/'

/** The host temporary directory following the pinned Native actual. */
public val SystemTemporaryDirectory: Path get() = Path(ioFsTemporaryDirectory())

@KsSymbolName("__kk_io_fs_temporary_directory")
private external fun ioFsTemporaryDirectory(): String

/** Matches the kotlinx-io Native Path representation: only trailing separators are removed. */
public fun Path(path: String): Path {
    return Path(removeTrailingSeparators(path), true)
}

/** Join a base string with path components using the system separator. */
public fun Path(base: String, vararg parts: String): Path {
    var result = base
    for (part in parts) {
        if (result.isNotEmpty() && !result.endsWith('/')) result += SystemPathSeparator
        result += part
    }
    return Path(result)
}

// Forwarding `vararg` through a spread (`*parts`) crashes at runtime in this
// compiler, so this overload repeats the join loop instead of delegating.
/** Join a path with additional components. */
public fun Path(base: Path, vararg parts: String): Path {
    var result = base.toString()
    for (part in parts) {
        if (result.isNotEmpty() && !result.endsWith('/')) result += SystemPathSeparator
        result += part
    }
    return Path(result)
}
