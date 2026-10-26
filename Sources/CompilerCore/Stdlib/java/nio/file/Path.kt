@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

package java.nio.file

import java.io.File
import java.lang.System
import java.net.URI

/** Native path producer for Java-facing interoperability; no classfile facade. */
public class Path internal constructor(internal val text: String) : Comparable<Path>, Iterable<Path> {
    public val isAbsolute: Boolean
        get() = text.startsWith("/")

    public val root: Path?
        get() = if (isAbsolute) Path("/") else null

    public val fileName: Path?
        get() {
            val names = pathNameSegments(text)
            return if (names.isEmpty()) null else Path(names[names.size - 1])
        }

    public val parent: Path?
        get() {
            if (text.isEmpty() || text == "/") return null
            val slash = text.lastIndexOf('/')
            if (slash < 0) return null
            return Path(if (slash == 0) "/" else text.substring(0, slash))
        }

    public val nameCount: Int
        get() = pathNameSegments(text).size

    public fun getName(index: Int): Path {
        val names = pathNameSegments(text)
        if (index < 0 || index >= names.size) {
            throw IndexOutOfBoundsException("name index: " + index + ", name count: " + names.size)
        }
        return Path(names[index])
    }

    public fun subpath(beginIndex: Int, endIndex: Int): Path {
        val names = pathNameSegments(text)
        if (beginIndex < 0 || endIndex > names.size || beginIndex >= endIndex) {
            throw IllegalArgumentException("Invalid subpath range: " + beginIndex + ".." + endIndex)
        }
        var result = names[beginIndex]
        for (index in beginIndex + 1 until endIndex) result += "/" + names[index]
        return Path(result)
    }

    public fun startsWith(other: Path): Boolean {
        if (other.text.isEmpty() || isAbsolute != other.isAbsolute) return false
        val names = pathNameSegments(text)
        val prefix = pathNameSegments(other.text)
        if (prefix.size > names.size) return false
        for (index in prefix.indices) {
            if (names[index] != prefix[index]) return false
        }
        return true
    }

    public fun startsWith(other: String): Boolean = startsWith(Paths.get(other))

    public fun endsWith(other: Path): Boolean {
        if (other.text.isEmpty()) return false
        if (other.isAbsolute) return text == other.text
        val names = pathNameSegments(text)
        val suffix = pathNameSegments(other.text)
        if (suffix.size > names.size) return false
        val offset = names.size - suffix.size
        for (index in suffix.indices) {
            if (names[offset + index] != suffix[index]) return false
        }
        return true
    }

    public fun endsWith(other: String): Boolean = endsWith(Paths.get(other))

    public fun normalize(): Path {
        val absolute = isAbsolute
        val names = mutableListOf<String>()
        for (name in pathNameSegments(text)) {
            when (name) {
                "." -> Unit
                ".." -> {
                    if (names.isNotEmpty() && names[names.size - 1] != "..") {
                        names.removeAt(names.size - 1)
                    } else if (!absolute) {
                        names.add(name)
                    }
                }
                else -> names.add(name)
            }
        }
        val prefix = if (absolute) "/" else ""
        return Path(prefix + names.joinToString("/"))
    }

    public fun resolve(other: Path): Path {
        if (other.isAbsolute) return other
        if (other.text.isEmpty()) return this
        if (text.isEmpty()) return other
        return Paths.get(text, other.text)
    }

    public fun resolve(other: String): Path = resolve(Paths.get(other))

    public fun resolve(first: String, vararg more: String): Path = resolve(Paths.get(first, *more))

    public fun resolveSibling(other: Path): Path {
        val parentPath = parent ?: return other
        return parentPath.resolve(other)
    }

    public fun resolveSibling(other: String): Path = resolveSibling(Paths.get(other))

    public fun relativize(other: Path): Path {
        if (isAbsolute != other.isAbsolute) {
            throw IllegalArgumentException("Cannot relativize paths with different roots")
        }
        val source = pathNameSegments(text)
        val target = pathNameSegments(other.text)
        var common = 0
        while (common < source.size && common < target.size && source[common] == target[common]) {
            common++
        }
        val result = mutableListOf<String>()
        for (index in common until source.size) result.add("..")
        for (index in common until target.size) result.add(target[index])
        return Path(result.joinToString("/"))
    }

    public fun toUri(): URI {
        val absolute = toAbsolutePath().normalize()
        return URI("file://" + encodePathForURI(absolute.text))
    }

    public fun toAbsolutePath(): Path {
        if (isAbsolute) return this
        val currentDirectory = System.getProperty("user.dir") ?: "/"
        return Paths.get(currentDirectory, text).normalize()
    }

    public fun toFile(): File = File(text)

    override fun iterator(): Iterator<Path> {
        val result = mutableListOf<Path>()
        for (name in pathNameSegments(text)) result.add(Path(name))
        return result.iterator()
    }

    override fun compareTo(other: Path): Int = text.compareTo(other.text)

    override fun toString(): String = text

    override fun hashCode(): Int = text.hashCode()

    override fun equals(other: Any?): Boolean = other is Path && text == other.text

    public companion object {
        public fun of(first: String, vararg more: String): Path = Paths.get(first, *more)

        public fun of(uri: URI): Path = Paths.get(uri)
    }
}

public object Paths {
    public fun get(first: String, vararg more: String): Path {
        var joined = first
        for (part in more) {
            if (part.isNotEmpty()) {
                if (joined.isNotEmpty()) joined += "/"
                joined += part
            }
        }

        // POSIX paths collapse repeated separators and discard trailing ones;
        // dot and parent segments remain lexical until the filesystem resolves them.
        var normalized = ""
        var separator = false
        for (character in joined) {
            require(character != '\u0000') { "Nul character not allowed in path" }
            if (character != '/' || !separator) normalized += character
            separator = character == '/'
        }
        if (normalized.length > 1 && normalized.endsWith('/')) {
            normalized = normalized.substring(0, normalized.length - 1)
        }
        return Path(normalized)
    }

    public fun get(uri: URI): Path {
        require(uri.scheme?.lowercase() == "file" && !uri.isOpaque) {
            "URI scheme is not file"
        }
        val authority = uri.rawAuthority
        require(authority == null || authority.isEmpty() || authority.equals("localhost", ignoreCase = true)) {
            "URI authority is not supported"
        }
        return get(uri.path ?: "")
    }
}

private fun pathNameSegments(path: String): List<String> {
    val names = mutableListOf<String>()
    for (segment in path.split('/')) {
        if (segment.isNotEmpty()) names.add(segment)
    }
    return names
}

private fun encodePathForURI(path: String): String {
    val bytes = path.encodeToByteArray()
    var result = ""
    for (byte in bytes) {
        val value = byte.toInt() and 0xff
        val character = value.toChar()
        if (character in 'a'..'z' || character in 'A'..'Z' || character in '0'..'9'
            || character == '/' || character == '-' || character == '.' || character == '_'
            || character == '~') {
            result += character
        } else {
            val high = "0123456789ABCDEF"[value shr 4]
            val low = "0123456789ABCDEF"[value and 15]
            result += "%" + high + low
        }
    }
    return result
}

public interface OpenOption
public enum class StandardOpenOption : OpenOption {
    READ, WRITE, APPEND, TRUNCATE_EXISTING, CREATE, CREATE_NEW, DELETE_ON_CLOSE, SPARSE, SYNC, DSYNC
}
public enum class LinkOption : OpenOption { NOFOLLOW_LINKS }
