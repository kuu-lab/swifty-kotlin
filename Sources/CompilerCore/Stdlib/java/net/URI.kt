@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

package java.net

/** Native source-backed compatibility type for JVM-shaped URI signatures. */
public class URI(private val spec: String) : Comparable<URI> {
    public constructor(
        scheme: String?,
        schemeSpecificPart: String?,
        fragment: String?
    ) : this(buildURI(scheme, schemeSpecificPart, fragment))

    public constructor(
        scheme: String?,
        authority: String?,
        path: String?,
        query: String?,
        fragment: String?
    ) : this(buildHierarchicalURI(scheme, authority, path, query, fragment))

    public constructor(
        scheme: String?,
        host: String?,
        path: String?,
        fragment: String?
    ) : this(buildHierarchicalURI(scheme, host, path, null, fragment))

    public constructor(
        scheme: String?,
        userInfo: String?,
        host: String?,
        port: Int,
        path: String?,
        query: String?,
        fragment: String?
    ) : this(
        buildHierarchicalURI(
            scheme,
            if (host == null) null else (if (userInfo == null) "" else userInfo + "@")
                + host
                + if (port < 0) "" else ":$port",
            path,
            query,
            fragment
        )
    )

    public val scheme: String?
        get() {
            val end = uriSchemeEnd(spec)
            return if (end < 0) null else spec.substring(0, end)
        }

    public val isAbsolute: Boolean
        get() = scheme != null

    public val isOpaque: Boolean
        get() = this.scheme != null && !(this.rawSchemeSpecificPart?.startsWith("/") ?: false)

    public val rawSchemeSpecificPart: String?
        get() {
            val end = uriFragmentStart(spec).let { if (it < 0) spec.length else it }
            val start = uriSchemeEnd(spec) + 1
            return spec.substring(if (start == 0) 0 else start, end)
        }

    public val schemeSpecificPart: String?
        get() = uriDecode(this.rawSchemeSpecificPart)

    public val rawAuthority: String?
        get() = uriRawAuthority(spec)

    public val authority: String?
        get() = uriDecode(this.rawAuthority)

    public val rawUserInfo: String?
        get() {
            val value = this.rawAuthority ?: return null
            val at = value.lastIndexOf('@')
            return if (at < 0) null else value.substring(0, at)
        }

    public val userInfo: String?
        get() = uriDecode(this.rawUserInfo)

    public val host: String?
        get() = uriHostAndPort(this.rawAuthority).first

    public val port: Int
        get() = uriHostAndPort(this.rawAuthority).second

    public val rawPath: String?
        get() = uriRawPath(spec)

    public val path: String?
        get() = uriDecode(this.rawPath)

    public val rawQuery: String?
        get() = uriRawQuery(spec)

    public val query: String?
        get() = uriDecode(this.rawQuery)

    public val rawFragment: String?
        get() {
            val start = uriFragmentStart(spec)
            return if (start < 0) null else spec.substring(start + 1)
        }

    public val fragment: String?
        get() = uriDecode(this.rawFragment)

    public fun normalize(): URI {
        val path = this.rawPath ?: return this
        val normalized = normalizeURIPath(path)
        if (normalized == path) return this
        return URI(buildRawURI(this.scheme, this.rawAuthority, normalized, this.rawQuery, this.rawFragment))
    }

    public fun resolve(reference: URI): URI {
        if (reference.scheme != null) return reference.normalize()
        if (this.isOpaque) return reference

        val referenceAuthority = reference.rawAuthority
        if (referenceAuthority != null) {
            return URI(
                buildRawURI(
                    this.scheme,
                    referenceAuthority,
                    reference.rawPath,
                    reference.rawQuery,
                    reference.rawFragment
                )
            ).normalize()
        }

        val referencePath = reference.rawPath ?: ""
        val basePath = this.rawPath ?: ""
        if (referencePath.isEmpty()) {
            return URI(
                buildRawURI(
                    this.scheme,
                    this.rawAuthority,
                    basePath,
                    reference.rawQuery ?: this.rawQuery,
                    reference.rawFragment
                )
            )
        }

        val mergedPath = if (referencePath.startsWith("/")) {
            referencePath
        } else {
            val slash = basePath.lastIndexOf('/')
            val directory = if (slash < 0) "" else basePath.substring(0, slash + 1)
            if (this.rawAuthority != null && basePath.isEmpty()) {
                "/" + referencePath
            } else {
                directory + referencePath
            }
        }
        return URI(
            buildRawURI(
                this.scheme,
                this.rawAuthority,
                mergedPath,
                reference.rawQuery,
                reference.rawFragment
            )
        ).normalize()
    }

    public fun resolve(reference: String): URI = resolve(URI(reference))

    public fun relativize(target: URI): URI {
        if (this.scheme != target.scheme || this.rawAuthority != target.rawAuthority
            || this.isOpaque || target.isOpaque) {
            return target
        }
        val basePath = this.rawPath ?: ""
        val targetPath = target.rawPath ?: ""
        val directory = if (basePath.endsWith("/")) basePath else {
            val slash = basePath.lastIndexOf('/')
            if (slash < 0) "" else basePath.substring(0, slash + 1)
        }
        if (!targetPath.startsWith(directory)) return target
        val relativePath = targetPath.substring(directory.length)
        return URI(buildRawURI(null, null, relativePath, target.rawQuery, target.rawFragment))
    }

    public fun toASCIIString(): String = spec

    override fun compareTo(other: URI): Int = spec.compareTo(other.spec)

    override fun equals(other: Any?): Boolean = other is URI && spec == other.spec

    override fun hashCode(): Int = spec.hashCode()

    public override fun toString(): String = spec

    public companion object {
        public fun create(spec: String): URI = URI(spec)
    }
}

private fun uriSchemeEnd(value: String): Int {
    val colon = value.indexOf(':')
    if (colon <= 0) return -1
    val end = uriFragmentStart(value).let { if (it < 0) value.length else it }
    if (colon >= end) return -1
    val firstDelimiter = uriFirstDelimiter(value, 0, end, '/', '?')
    if (firstDelimiter >= 0 && colon > firstDelimiter) return -1
    if (!(value[0] in 'a'..'z' || value[0] in 'A'..'Z')) return -1
    for (index in 1 until colon) {
        val character = value[index]
        if (!(character in 'a'..'z' || character in 'A'..'Z'
                || character in '0'..'9' || character == '+' || character == '-' || character == '.')) {
            return -1
        }
    }
    return colon
}

private fun uriFragmentStart(value: String): Int = value.indexOf('#')

private fun uriFirstDelimiter(value: String, start: Int, end: Int, first: Char, second: Char): Int {
    for (index in start until end) {
        if (value[index] == first || value[index] == second) return index
    }
    return -1
}

private fun uriRawAuthority(value: String): String? {
    val fragmentStart = uriFragmentStart(value).let { if (it < 0) value.length else it }
    val schemeEnd = uriSchemeEnd(value)
    val bodyStart = if (schemeEnd < 0) 0 else schemeEnd + 1
    if (bodyStart + 1 >= fragmentStart || value[bodyStart] != '/' || value[bodyStart + 1] != '/') return null
    val authorityStart = bodyStart + 2
    val authorityEnd = uriFirstDelimiter(value, authorityStart, fragmentStart, '/', '?')
    return value.substring(authorityStart, if (authorityEnd < 0) fragmentStart else authorityEnd)
}

private fun uriRawPath(value: String): String? {
    val schemeEnd = uriSchemeEnd(value)
    val bodyStart = if (schemeEnd < 0) 0 else schemeEnd + 1
    if (schemeEnd >= 0 && bodyStart < value.length && value[bodyStart] != '/'
        && !(value[bodyStart] == '/' && bodyStart + 1 < value.length && value[bodyStart + 1] == '/')) {
        return null
    }
    val fragmentEnd = uriFragmentStart(value).let { if (it < 0) value.length else it }
    var pathStart = bodyStart
    if (pathStart + 1 < fragmentEnd && value[pathStart] == '/' && value[pathStart + 1] == '/') {
        val authorityEnd = uriFirstDelimiter(value, pathStart + 2, fragmentEnd, '/', '?')
        pathStart = if (authorityEnd < 0) fragmentEnd else authorityEnd
    }
    val queryStart = value.indexOf('?', pathStart)
    val pathEnd = if (queryStart >= 0 && queryStart < fragmentEnd) queryStart else fragmentEnd
    return value.substring(pathStart, pathEnd)
}

private fun uriRawQuery(value: String): String? {
    if (uriSchemeEnd(value) >= 0 && uriRawPath(value) == null) return null
    val fragmentEnd = uriFragmentStart(value).let { if (it < 0) value.length else it }
    val start = value.indexOf('?')
    return if (start < 0 || start >= fragmentEnd) null else value.substring(start + 1, fragmentEnd)
}

private fun uriHostAndPort(authority: String?): Pair<String?, Int> {
    if (authority == null) return Pair(null, -1)
    val at = authority.lastIndexOf('@')
    val server = if (at < 0) authority else authority.substring(at + 1)
    if (server.isEmpty()) return Pair(null, -1)

    var host: String
    var port = -1
    if (server.startsWith("[")) {
        val close = server.indexOf(']')
        if (close < 0) return Pair(null, -1)
        host = server.substring(0, close + 1)
        val suffix = server.substring(close + 1)
        if (suffix.isNotEmpty()) {
            if (!suffix.startsWith(":")) return Pair(null, -1)
            port = uriParsePort(suffix.substring(1)) ?: return Pair(null, -1)
        }
    } else {
        val colon = server.lastIndexOf(':')
        if (colon >= 0) {
            if (server.indexOf(':') != colon) return Pair(null, -1)
            host = server.substring(0, colon)
            port = uriParsePort(server.substring(colon + 1)) ?: return Pair(null, -1)
        } else {
            host = server
        }
    }
    if (host.isEmpty()) return Pair(null, -1)
    for (character in host) {
        if (character.isWhitespace() || character == '/' || character == '?' || character == '#') {
            return Pair(null, -1)
        }
    }
    return Pair(host, port)
}

private fun uriParsePort(value: String): Int? {
    if (value.isEmpty()) return -1
    var port = 0
    for (character in value) {
        if (character !in '0'..'9') return null
        val digit = character.code - '0'.code
        if (port > (Int.MAX_VALUE - digit) / 10) return null
        port = port * 10 + digit
    }
    return port
}

private fun uriDecode(value: String?): String? {
    if (value == null) return null
    var result = ""
    var index = 0
    while (index < value.length) {
        if (value[index] == '%' && index + 2 < value.length) {
            val bytes = mutableListOf<Byte>()
            var cursor = index
            while (cursor + 2 < value.length && value[cursor] == '%') {
                val high = uriHexValue(value[cursor + 1])
                val low = uriHexValue(value[cursor + 2])
                if (high < 0 || low < 0) break
                bytes.add(((high shl 4) or low).toByte())
                cursor += 3
            }
            if (bytes.isNotEmpty()) {
                val decoded = ByteArray(bytes.size) { bytes[it] }.decodeToString()
                result += decoded
                index = cursor
                continue
            }
        }
        result += value[index]
        index++
    }
    return result
}

private fun uriHexValue(character: Char): Int = when (character) {
    in '0'..'9' -> character.code - '0'.code
    in 'a'..'f' -> character.code - 'a'.code + 10
    in 'A'..'F' -> character.code - 'A'.code + 10
    else -> -1
}

private fun buildURI(scheme: String?, schemeSpecificPart: String?, fragment: String?): String {
    var result = if (scheme == null) "" else scheme + ":"
    result += schemeSpecificPart ?: ""
    if (fragment != null) result += "#" + fragment
    return result
}

private fun buildHierarchicalURI(
    scheme: String?,
    authority: String?,
    path: String?,
    query: String?,
    fragment: String?
): String {
    var result = if (scheme == null) "" else scheme + ":"
    if (authority != null) result += "//" + authority
    var pathValue = path ?: ""
    if (authority != null && pathValue.isNotEmpty() && !pathValue.startsWith("/")) {
        pathValue = "/" + pathValue
    }
    result += pathValue
    if (query != null) result += "?" + query
    if (fragment != null) result += "#" + fragment
    return result
}

private fun buildRawURI(
    scheme: String?,
    authority: String?,
    path: String?,
    query: String?,
    fragment: String?
): String {
    var result = if (scheme == null) "" else scheme + ":"
    if (authority != null) result += "//" + authority
    result += path ?: ""
    if (query != null) result += "?" + query
    if (fragment != null) result += "#" + fragment
    return result
}

private fun normalizeURIPath(path: String): String {
    if (path.isEmpty()) return path
    val absolute = path.startsWith("/")
    val trailingSlash = path.endsWith("/")
    val segments = mutableListOf<String>()
    for (segment in path.split('/')) {
        when (segment) {
            "", "." -> Unit
            ".." -> {
                if (segments.isNotEmpty() && segments[segments.size - 1] != "..") {
                    segments.removeAt(segments.size - 1)
                } else if (!absolute) {
                    segments.add(segment)
                }
            }
            else -> segments.add(segment)
        }
    }
    var result = (if (absolute) "/" else "") + segments.joinToString("/")
    if (trailingSlash && result.isNotEmpty() && !result.endsWith("/")) result += "/"
    if (absolute && result.isEmpty()) return "/"
    return result
}
