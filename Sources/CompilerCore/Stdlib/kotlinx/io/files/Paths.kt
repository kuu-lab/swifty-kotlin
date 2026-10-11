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
