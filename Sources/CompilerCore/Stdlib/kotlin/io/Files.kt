package kotlin.io

// KSP-483: File path pure-logic layer.
// Migration source: Sources/Runtime/RuntimeFileIO.swift
//   kk_file_name, kk_file_extension, kk_file_nameWithoutExtension, kk_file_parent,
//   kk_file_invariantSeparatorsPath, kk_file_isRooted, kk_file_startsWith_file,
//   kk_file_startsWith_string, kk_file_resolveSibling_file, kk_file_resolveSibling_string,
//   kk_file_toRelativeString, kk_file_normalize
// `path` reads File's internal state, so it stays the existing synthetic member
// (a Kotlin-source `path` extension property would collide with the
// `kotlin.io.path` package FQName). Every member below is pure string logic
// derived from `path`.

import java.io.File

// NOTE: `String.lastIndexOf(Char)` (single-argument) is not usable here — this
// compiler only registers the 3-arg `lastIndexOf(Char, startIndex, ignoreCase)`
// overload without default parameter values, so a 1-arg call site resolves to
// the unrelated `lastIndexOf(other: String)` overload and misbehaves at
// runtime. Route every last-`Char`-index lookup through this helper instead.
private fun stringLastIndexOfChar(s: String, char: Char): Int =
    if (s.isEmpty()) -1 else s.lastIndexOf(char, s.length - 1, false)

private fun fileLastPathComponent(path: String): String {
    if (path.isEmpty()) return ""
    val trimmed = if (path.length > 1 && path.endsWith("/")) path.trimEnd { it == '/' }.ifEmpty { "/" } else path
    if (trimmed == "/") return "/"
    val idx = stringLastIndexOfChar(trimmed, '/')
    return if (idx < 0) trimmed else trimmed.substring(idx + 1)
}

public val File.name: String
    get() = fileLastPathComponent(path)

public val File.extension: String
    get() {
        // NOTE: must read `this.name` explicitly — referencing the sibling
        // Kotlin-source extension property `name` through the implicit
        // receiver (bare `name`) does not resolve correctly in this compiler.
        val n = this.name
        val dotIndex = stringLastIndexOfChar(n, '.')
        return if (dotIndex < 0) "" else n.substring(dotIndex + 1)
    }

public val File.nameWithoutExtension: String
    get() {
        val n = this.name
        val dotIndex = stringLastIndexOfChar(n, '.')
        return if (dotIndex < 0) n else n.substring(0, dotIndex)
    }

private fun fileDeletingLastPathComponent(path: String): String {
    val trimmed = if (path.length > 1 && path.endsWith("/")) path.trimEnd { it == '/' }.ifEmpty { "/" } else path
    if (trimmed == "/") return "/"
    val idx = stringLastIndexOfChar(trimmed, '/')
    if (idx < 0) return ""
    if (idx == 0) return "/"
    return trimmed.substring(0, idx)
}

public val File.parent: String?
    get() {
        val p = path
        val result = fileDeletingLastPathComponent(p)
        return if (result.isEmpty() || result == p) null else result
    }

public val File.invariantSeparatorsPath: String
    get() = path.replace("\\", "/")

public val File.isRooted: Boolean
    get() {
        // NOTE: `&&`/`||` do not short-circuit in this compiler (both operands
        // are always evaluated), so bounds checks must be structured as nested
        // `if`s rather than relying on left-to-right guarding.
        val p = path
        if (p.isEmpty()) return false
        val first = p[0]
        if (first == '/' || first == '\\') return true
        if (p.length < 2) return false
        if (p[1] != ':') return false
        return p[0] in 'a'..'z' || p[0] in 'A'..'Z'
    }

private fun filePathComponents(path: String): List<String> =
    path.split("/").filter { it.isNotEmpty() }

private fun fileStartsWithComponents(path: String, other: String): Boolean {
    val pathParts = filePathComponents(path)
    val otherParts = filePathComponents(other)
    val pathIsAbsolute = path.startsWith("/")
    val otherIsAbsolute = other.startsWith("/")
    if (pathIsAbsolute != otherIsAbsolute || otherParts.size > pathParts.size) {
        return false
    }
    for (index in otherParts.indices) {
        if (pathParts[index] != otherParts[index]) return false
    }
    return true
}

public fun File.startsWith(other: File): Boolean = fileStartsWithComponents(path, other.path)

public fun File.startsWith(other: String): Boolean = fileStartsWithComponents(path, other)

private fun fileResolveSiblingPath(base: String, sibling: String): String {
    val trimmed = if (base.endsWith("/") && base.length > 1) base.dropLast(1) else base
    val idx = stringLastIndexOfChar(trimmed, '/')
    if (idx < 0) return sibling
    val parent = trimmed.substring(0, idx)
    return if (parent.isEmpty()) "/$sibling" else "$parent/$sibling"
}

public fun File.resolveSibling(relative: File): File = File(fileResolveSiblingPath(path, relative.path))

public fun File.resolveSibling(relative: String): File = File(fileResolveSiblingPath(path, relative))

private fun filePathRootAndSegments(path: String): Pair<String, List<String>> {
    if (path.isEmpty()) return Pair("", emptyList())
    val isAbsolute = path.startsWith("/")
    val root = if (isAbsolute) "/" else ""
    val trimmed = if (isAbsolute) path.substring(1) else path
    val segments = trimmed.split("/").filter { it.isNotEmpty() }
    return Pair(root, segments)
}

public fun File.toRelativeString(base: File): String {
    val target = filePathRootAndSegments(path)
    val baseComponents = filePathRootAndSegments(base.path)

    if (target.first != baseComponents.first) {
        throw IllegalArgumentException(
            "this and base files have different roots: $path and ${base.path}."
        )
    }

    val targetSegments = target.second
    val baseSegments = baseComponents.second

    var commonCount = 0
    val maxCommon = minOf(targetSegments.size, baseSegments.size)
    while (commonCount < maxCommon) {
        if (targetSegments[commonCount] != baseSegments[commonCount]) break
        commonCount++
    }

    val pieces = mutableListOf<String>()
    val baseExtraCount = baseSegments.size - commonCount
    if (baseExtraCount > 0) {
        repeat(baseExtraCount) { pieces.add("..") }
    }
    if (commonCount < targetSegments.size) {
        pieces.addAll(targetSegments.subList(commonCount, targetSegments.size))
    }

    return pieces.joinToString("/")
}

private fun fileNormalizePath(path: String): String {
    val isAbsolute = path.startsWith("/")
    val parts = path.split("/").filter { it.isNotEmpty() }
    val stack = mutableListOf<String>()
    for (part in parts) {
        when (part) {
            "." -> { }
            ".." -> {
                if (isAbsolute) {
                    if (stack.isNotEmpty()) stack.removeAt(stack.size - 1)
                } else {
                    val shouldAppend = if (stack.isEmpty()) true else stack.last() == ".."
                    if (shouldAppend) {
                        stack.add("..")
                    } else {
                        stack.removeAt(stack.size - 1)
                    }
                }
            }
            else -> stack.add(part)
        }
    }
    val joined = stack.joinToString("/")
    return if (isAbsolute) "/$joined" else if (joined.isEmpty()) "." else joined
}

public fun File.normalize(): File = File(fileNormalizePath(path))
