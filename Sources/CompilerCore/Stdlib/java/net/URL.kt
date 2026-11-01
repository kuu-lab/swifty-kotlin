package java.net

import java.io.InputStream
import kotlin.internal.KsSymbolName

/** Native source-backed `java.net.URL`: immutable URL with JVM-shaped
 * component accessors, relative resolution, `sameFile`/`equals`/`hashCode`,
 * `openStream`/`openConnection` routed through the runtime URL fetcher. */
public final class URL {
    private val spec: String
    public val protocol: String
    private val authorityPart: String?
    private val userInfoPart: String?
    public val host: String
    public val port: Int
    public val path: String
    private val queryPart: String?
    private val refPart: String?

    public constructor(spec: String) {
        val parsed = urlParse(spec) ?: throw MalformedURLException(spec)
        this.spec = parsed.serialized
        this.protocol = parsed.protocol
        this.authorityPart = parsed.authority
        this.userInfoPart = parsed.userInfo
        this.host = parsed.host
        this.port = parsed.port
        this.path = parsed.path
        this.queryPart = parsed.query
        this.refPart = parsed.ref
    }

    public constructor(protocol: String?, host: String?, port: Int, file: String?) : this(
        buildURLSpec(protocol, host, port, file)
    )

    public constructor(protocol: String?, host: String?, file: String?) : this(
        buildURLSpec(protocol, host, -1, file)
    )

    public constructor(base: URL?, spec: String) : this(
        if (base == null) spec else urlResolve(base.spec, spec)
    )

    public constructor(base: URL?, spec: String?) : this(
        urlResolveNullable(base?.spec, spec)
    )

    public val authority: String?
        get() = authorityPart

    public val userInfo: String?
        get() = userInfoPart

    public val defaultPort: Int
        get() = when (protocol) {
            "http" -> 80
            "https" -> 443
            "ftp" -> 21
            else -> -1
        }

    /** `path` plus `?query`, matching the JDK `getFile` contract. */
    public val file: String
        get() = path + (queryPart?.let { "?$it" } ?: "")

    public val query: String?
        get() = queryPart

    public val ref: String?
        get() = refPart


    public fun toExternalForm(): String = spec

    public fun toURI(): URI = URI(spec)

    /** `true` when two URLs name the same resource: equal protocol, host
     * (case-insensitive), effective port, file, and ref — ignoring user-info
     * differences the JDK ignores for `sameFile`. */
    public fun sameFile(other: URL): Boolean =
        protocol.equals(other.protocol, ignoreCase = true) &&
            host.equals(other.host, ignoreCase = true) &&
            effectivePort() == other.effectivePort() &&
            file == other.file && refPart == other.refPart

    private fun effectivePort(): Int = if (port >= 0) port else defaultPort

    override fun equals(other: Any?): Boolean = other is URL && sameFile(other)

    override fun hashCode(): Int {
        var result = protocol.lowercase().hashCode()
        result = 31 * result + host.lowercase().hashCode()
        result = 31 * result + effectivePort()
        result = 31 * result + file.hashCode()
        return result
    }

    override fun toString(): String = spec

    /** Opens a connection to this URL and returns an InputStream over the
     * response body. Works for `http`, `https` (network), and `file` URLs. */
    public fun openStream(): InputStream = netUrlOpenStream(spec)

    public fun openConnection(): URLConnection =
        if (protocol == "http" || protocol == "https") HttpURLConnection(this) else URLConnection(this)
}

private class ParsedURL(
    val serialized: String,
    val protocol: String,
    val authority: String?,
    val userInfo: String?,
    val host: String,
    val port: Int,
    val path: String,
    val query: String?,
    val ref: String?
)

private val urlKnownProtocols = setOf("http", "https", "file", "ftp", "jar")

private fun urlIsSchemeChar(c: Char): Boolean =
    c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || c == '+' || c == '-' || c == '.'

private fun urlParse(spec: String): ParsedURL? {
    val colon = spec.indexOf(':')
    if (colon <= 0 || !spec[0].isLetter()) return null
    val protocol = spec.substring(0, colon).lowercase()
    for (i in 1 until colon) if (!urlIsSchemeChar(spec[i])) return null
    if (!urlKnownProtocols.contains(protocol)) {
        return null
    }
    var rest = spec.substring(colon + 1)

    var ref: String? = null
    val hash = rest.indexOf('#')
    if (hash >= 0) {
        ref = rest.substring(hash + 1)
        rest = rest.substring(0, hash)
    }

    var authority: String? = null
    var userInfo: String? = null
    var host = ""
    var port = -1
    var pathAndQuery: String

    if (rest.startsWith("//")) {
        val afterSlashes = rest.substring(2)
        var authEnd = afterSlashes.length
        val slashIdx = afterSlashes.indexOf('/')
        val questionIdx = afterSlashes.indexOf('?')
        if (slashIdx >= 0 && slashIdx < authEnd) authEnd = slashIdx
        if (questionIdx >= 0 && questionIdx < authEnd) authEnd = questionIdx
        authority = afterSlashes.substring(0, authEnd)
        pathAndQuery = afterSlashes.substring(authEnd)

        var server: String = authority ?: ""
        val at = server.lastIndexOf('@')
        if (at >= 0) {
            userInfo = server.substring(0, at)
            server = server.substring(at + 1)
        }
        if (server.startsWith("[")) {
            val close = server.indexOf(']')
            if (close < 0) return null
            host = server.substring(1, close)
            val suffix = server.substring(close + 1)
            if (suffix.isNotEmpty()) {
                if (!suffix.startsWith(":")) return null
                port = suffix.substring(1).toIntOrNull() ?: return null
            }
        } else {
            val colonIdx = server.lastIndexOf(':')
            if (colonIdx >= 0) {
                host = server.substring(0, colonIdx)
                port = server.substring(colonIdx + 1).toIntOrNull() ?: return null
            } else {
                host = server
            }
        }
        if (host.isEmpty() && protocol != "file") return null
    } else {
        pathAndQuery = rest
    }

    var query: String? = null
    val qIdx = pathAndQuery.indexOf('?')
    var path = pathAndQuery
    if (qIdx >= 0) {
        query = pathAndQuery.substring(qIdx + 1)
        path = pathAndQuery.substring(0, qIdx)
    }
    if (authority != null && path.isEmpty()) path = ""

    val serialized = buildString {
        append(protocol)
        append(':')
        if (authority != null) {
            append("//")
            append(authority)
        }
        append(path)
        if (query != null) {
            append('?')
            append(query)
        }
        if (ref != null) {
            append('#')
            append(ref)
        }
    }
    return ParsedURL(serialized, protocol, authority, userInfo, host, port, path, query, ref)
}

private fun buildURLSpec(protocol: String?, host: String?, port: Int, file: String?): String {
    val proto = (protocol ?: "file").lowercase()
    var result = "$proto:"
    if (host != null) {
        result += "//$host"
        if (port >= 0) result += ":$port"
    }
    var fileValue = file ?: ""
    if (host != null && fileValue.isNotEmpty() && !fileValue.startsWith("/")) {
        fileValue = "/$fileValue"
    }
    result += fileValue
    return result
}

private fun urlResolveNullable(base: String?, spec: String?): String {
    if (spec == null) return base ?: throw MalformedURLException("null")
    return if (base == null) spec else urlResolve(base, spec)
}

private fun urlResolve(base: String, spec: String): String {
    if (urlParse(spec) != null || spec.contains(':') && spec.substringBefore(':').all { urlIsSchemeChar(it) } && spec.indexOf(':') > 0) {
        return spec
    }
    val baseParsed = urlParse(base) ?: return spec
    val hashIdx = spec.indexOf('#')
    val specRef = if (hashIdx >= 0) spec.substring(hashIdx) else ""
    val specNoRef = if (hashIdx >= 0) spec.substring(0, hashIdx) else spec

    if (specNoRef.startsWith("//")) {
        return baseParsed.protocol + ":" + specNoRef + specRef
    }

    val (basePath, baseQuery) = run {
        val q = baseParsed.query
        Pair(baseParsed.path, q)
    }
    val baseFilePrefix = buildString {
        append(baseParsed.protocol)
        append(':')
        if (baseParsed.authority != null) {
            append("//")
            append(baseParsed.authority)
        }
    }

    var newPath: String
    var newQuery: String? = null
    if (specNoRef.startsWith("/")) {
        val qIdx = specNoRef.indexOf('?')
        if (qIdx >= 0) {
            newPath = specNoRef.substring(0, qIdx)
            newQuery = specNoRef.substring(qIdx + 1)
        } else {
            newPath = specNoRef
        }
    } else if (specNoRef.isEmpty()) {
        newPath = basePath
        newQuery = baseQuery
    } else {
        val qIdx = specNoRef.indexOf('?')
        var relPath = specNoRef
        if (qIdx >= 0) {
            relPath = specNoRef.substring(0, qIdx)
            newQuery = specNoRef.substring(qIdx + 1)
        }
        if (relPath.isEmpty()) {
            newPath = basePath
        } else {
            val slash = basePath.lastIndexOf('/')
            val dir = if (slash < 0) "" else basePath.substring(0, slash + 1)
            newPath = urlNormalizePath(dir + relPath)
        }
    }

    val result = StringBuilder()
    result.append(baseFilePrefix)
    result.append(newPath)
    if (newQuery != null) {
        result.append('?')
        result.append(newQuery)
    }
    result.append(specRef)
    return result.toString()
}

private fun urlNormalizePath(path: String): String {
    val absolute = path.startsWith("/")
    val segments = mutableListOf<String>()
    for (segment in path.split('/')) {
        when (segment) {
            "", "." -> Unit
            ".." -> if (segments.isNotEmpty() && segments.last() != "..") segments.removeAt(segments.size - 1)
            else -> segments.add(segment)
        }
    }
    val joined = segments.joinToString("/")
    return (if (absolute) "/" else "") + joined
}

/** `application/x-www-form-urlencoded` codec matching the JDK. */
public object URLEncoder {
    private val safe = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-*_"

    public fun encode(s: String, enc: String): String = encode(s)

    public fun encode(s: String): String {
        val out = StringBuilder()
        for (byte in s.encodeToByteArray()) {
            val c = byte.toInt() and 0xff
            when {
                c == 0x20 -> out.append('+')
                c < 0x80 && safe.indexOf(c.toChar()) >= 0 -> out.append(c.toChar())
                else -> {
                    out.append('%')
                    val hex = "0123456789ABCDEF"
                    out.append(hex[c shr 4])
                    out.append(hex[c and 0xf])
                }
            }
        }
        return out.toString()
    }
}

public object URLDecoder {
    public fun decode(s: String, enc: String): String = decode(s)

    public fun decode(s: String): String {
        val bytes = mutableListOf<Byte>()
        var i = 0
        while (i < s.length) {
            when (s[i]) {
                '+' -> {
                    bytes.add(0x20)
                    i++
                }
                '%' -> {
                    if (i + 2 >= s.length) throw IllegalArgumentException("URLDecoder: Incomplete trailing escape (%) pattern")
                    val hi = urlHexValue(s[i + 1])
                    val lo = urlHexValue(s[i + 2])
                    if (hi < 0 || lo < 0) throw IllegalArgumentException("URLDecoder: Illegal hex characters in escape (%) pattern")
                    bytes.add(((hi shl 4) or lo).toByte())
                    i += 3
                }
                else -> {
                    bytes.add(s[i].code.toByte())
                    i++
                }
            }
        }
        return ByteArray(bytes.size) { bytes[it] }.decodeToString()
    }
}

private fun urlHexValue(c: Char): Int = when (c) {
    in '0'..'9' -> c.code - '0'.code
    in 'a'..'f' -> c.code - 'a'.code + 10
    in 'A'..'F' -> c.code - 'A'.code + 10
    else -> -1
}

@KsSymbolName("__kk_net_url_open_stream")
private external fun netUrlOpenStream(spec: String): InputStream
