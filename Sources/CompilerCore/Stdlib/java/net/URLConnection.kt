package java.net

import java.io.InputStream
import java.io.OutputStream
import kotlin.internal.KsSymbolName

/** Native source-backed `java.net.URLConnection`. Request headers, timeouts,
 * and I/O flags are configured before [connect]; the runtime performs the
 * actual fetch for `http`/`https`/`file` URLs and caches the response for
 * `getInputStream`/header accessors, matching the JDK lazy-connect contract. */
public open class URLConnection {
    public val url: URL
    internal var handle: Long
    private var connected = false
    private val requestProps = LinkedHashMap<String, String>()
    public var connectTimeout: Int = 0
    public var readTimeout: Int = 0
    public var doInput: Boolean = true
    public var doOutput: Boolean = false
    public var useCaches: Boolean = true
    public var allowUserInteraction: Boolean = false
    private var outputStream: OutputStream? = null

    internal constructor(url: URL) {
        this.url = url
        this.handle = netUrlConnectionNew(url.toExternalForm())
    }

    internal constructor(url: URL, method: String) {
        this.url = url
        this.handle = netUrlConnectionNew(url.toExternalForm())
        netUrlConnectionSetMethod(handle, method)
    }

    public val inputStream: InputStream get() = getInputStream()
    public val outputStreamValue: OutputStream get() = getOutputStream()
    public val content: Any? get() = getContent()
    public val contentType: String? get() = getContentType()
    public val contentEncoding: String? get() = getContentEncoding()
    public val contentLength: Int get() = getContentLength()
    public val contentLengthLong: Long get() = getContentLengthLong()
    public val headerFields: Map<String, List<String>> get() = getHeaderFields()
    public val date: Long get() = getDate()
    public val expiration: Long get() = getExpiration()
    public val lastModified: Long get() = getLastModified()

    public open fun connect() {
        if (connected) return
        if (doOutput) netUrlConnectionSetDoOutput(handle, 1)
        connected = true
        netUrlConnectionConnect(handle, serializedRequestProperties(), connectTimeout, readTimeout)
    }

    private fun ensureConnected() {
        if (!connected) connect()
    }

    private fun serializedRequestProperties(): String =
        requestProps.entries.joinToString("\u0002") { "${it.key}\u0001${it.value}" }

    public open fun getInputStream(): InputStream {
        ensureConnected()
        return netUrlConnectionInputStream(handle)
    }

    public open fun getOutputStream(): OutputStream {
        val existing = outputStream
        if (existing != null) return existing
        if (connected) throw java.io.IOException("Already connected")
        doOutput = true
        netUrlConnectionSetDoOutput(handle, 1)
        val stream = netUrlConnectionOutputStream(handle)
        outputStream = stream
        return stream
    }



    public fun setRequestProperty(key: String, value: String) {
        if (connected) throw IllegalStateException("Already connected")
        requestProps[key] = value
    }

    public fun addRequestProperty(key: String, value: String) {
        if (connected) throw IllegalStateException("Already connected")
        if (!requestProps.containsKey(key)) requestProps[key] = value
    }

    public fun getRequestProperty(key: String): String? = requestProps[key]

    public fun getRequestProperties(): Map<String, List<String>> {
        val result = LinkedHashMap<String, List<String>>()
        for (entry in requestProps.entries) result[entry.key] = listOf(entry.value)
        return result
    }










    public var ifModifiedSince: Long = 0

    /** Response content bytes as an object — for the compatibility surface the
     * body text itself, matching `getInputStream` content. */
    public open fun getContent(): Any? {
        ensureConnected()
        return netUrlConnectionBodyText(handle)
    }

    public open fun getContentType(): String? {
        ensureConnected()
        return netUrlConnectionHeader(handle, "Content-Type") ?: urlGuessContentType(url.path)
    }

    public open fun getContentEncoding(): String? {
        ensureConnected()
        return netUrlConnectionHeader(handle, "Content-Encoding")
    }

    public open fun getContentLength(): Int {
        ensureConnected()
        return netUrlConnectionHeaderLong(handle, "Content-Length").toInt()
    }

    public open fun getContentLengthLong(): Long {
        ensureConnected()
        return netUrlConnectionHeaderLong(handle, "Content-Length")
    }

    public open fun getHeaderField(name: String?): String? {
        ensureConnected()
        return netUrlConnectionHeader(handle, name ?: return null)
    }

    public open fun getHeaderField(index: Int): String? {
        ensureConnected()
        return netUrlConnectionHeaderAt(handle, index)
    }

    public open fun getHeaderFieldKey(index: Int): String? {
        ensureConnected()
        return netUrlConnectionHeaderKeyAt(handle, index)
    }

    public open fun getHeaderFields(): Map<String, List<String>> {
        ensureConnected()
        return parseHeaderFieldsMap(netUrlConnectionHeadersMap(handle))
    }

    public open fun getHeaderFieldInt(name: String, default: Int): Int =
        getHeaderField(name)?.toIntOrNull() ?: default

    public open fun getHeaderFieldLong(name: String, default: Long): Long =
        getHeaderField(name)?.toLongOrNull() ?: default

    public open fun getDate(): Long = getHeaderFieldLong("Date", 0)
    public open fun getExpiration(): Long = getHeaderFieldLong("Expires", 0)
    public open fun getLastModified(): Long = getHeaderFieldLong("Last-Modified", 0)

    public open fun setDefaultUseCaches(defaultValue: Boolean) {
        useCaches = defaultValue
    }

    public companion object {
            public fun guessContentTypeFromStream(stream: InputStream): String? = null
    }

    override fun toString(): String = "URLConnection:${url.toExternalForm()}"
}

/** `HttpURLConnection` — adds request-method and response-status support. */
public open class HttpURLConnection : URLConnection {
    private var method = "GET"
    private var chunkLength = -1
    private var fixedContentLength = -1L

    public constructor(url: URL) : super(url, "GET")

    public var requestMethod: String
        get() = method
        set(value) {
            method = value.uppercase()
            netUrlConnectionSetMethod(handle, method)
        }


    public open fun disconnect() {
        netUrlConnectionDisconnect(handle)
    }

    public val responseCode: Int
        get() {
            getInputStreamIfNeeded()
            return responseCodeOrZero()
        }


    private fun responseCodeOrZero(): Int = netUrlConnectionResponseCode(handle)

    public fun getResponseMessage(): String? {
        connect()
        return netUrlConnectionResponseMessage(handle)
    }

    public fun getErrorStream(): InputStream? {
        val code = try { responseCode } catch (_: Throwable) { -1 }
        if (code < 400) return null
        return netUrlConnectionInputStream(handle)
    }

    private fun getInputStreamIfNeeded() {
        connect()
    }

    override fun getInputStream(): InputStream {
        val code = try { connect(); responseCodeOrZero() } catch (e: Throwable) { throw e }
        if (code >= 400) {
            throw java.io.IOException("Server returned HTTP response code: " + code + " for URL: " + url.toExternalForm())
        }
        return netUrlConnectionInputStream(handle)
    }



    public fun usingProxy(): Boolean = false

    public companion object {
        public var instanceFollowRedirects: Boolean = true

        public fun setFollowRedirects(value: Boolean) {
            instanceFollowRedirects = value
        }

        public fun getFollowRedirects(): Boolean = instanceFollowRedirects
    }

    public fun setFixedLengthStreamingMode(contentLength: Long) {
        fixedContentLength = contentLength
    }

    public fun setChunkedStreamingMode(chunkLength: Int) {
        this.chunkLength = chunkLength
    }

    override fun toString(): String = "HttpURLConnection:${url.toExternalForm()}"
}

internal fun parseHeaderFieldsMap(serialized: String): Map<String, List<String>> {
    val result = LinkedHashMap<String, MutableList<String>>()
    if (serialized.isEmpty()) return result
    for (entry in serialized.split("\u0002")) {
        val sep = entry.indexOf('\u0001')
        if (sep < 0) continue
        val key = entry.substring(0, sep)
        val value = entry.substring(sep + 1)
        val list = result[key] ?: mutableListOf<String>().also { result[key] = it }
        list.add(value)
    }
    return result
}

internal fun urlGuessContentType(fileName: String): String {
    val lower = fileName.lowercase()
    return when {
        lower.endsWith(".html") || lower.endsWith(".htm") -> "text/html"
        lower.endsWith(".txt") -> "text/plain"
        lower.endsWith(".css") -> "text/css"
        lower.endsWith(".xml") -> "application/xml"
        lower.endsWith(".json") -> "application/json"
        lower.endsWith(".png") -> "image/png"
        lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
        lower.endsWith(".gif") -> "image/gif"
        lower.endsWith(".svg") -> "image/svg+xml"
        lower.endsWith(".pdf") -> "application/pdf"
        lower.endsWith(".zip") -> "application/zip"
        else -> "application/octet-stream"
    }
}

@KsSymbolName("__kk_net_url_connection_new")
private external fun netUrlConnectionNew(spec: String): Long

@KsSymbolName("__kk_net_url_connection_set_method")
private external fun netUrlConnectionSetMethod(handle: Long, method: String)

@KsSymbolName("__kk_net_url_connection_set_do_output")
private external fun netUrlConnectionSetDoOutput(handle: Long, value: Int)

@KsSymbolName("__kk_net_url_connection_connect")
private external fun netUrlConnectionConnect(handle: Long, serializedHeaders: String, connectTimeoutMs: Int, readTimeoutMs: Int)

@KsSymbolName("__kk_net_url_connection_input_stream")
private external fun netUrlConnectionInputStream(handle: Long): InputStream

@KsSymbolName("__kk_net_url_connection_output_stream")
private external fun netUrlConnectionOutputStream(handle: Long): OutputStream

@KsSymbolName("__kk_net_url_connection_body_text")
private external fun netUrlConnectionBodyText(handle: Long): String?

@KsSymbolName("__kk_net_url_connection_header")
private external fun netUrlConnectionHeader(handle: Long, name: String): String?

@KsSymbolName("__kk_net_url_connection_header_long")
private external fun netUrlConnectionHeaderLong(handle: Long, name: String): Long

@KsSymbolName("__kk_net_url_connection_header_at")
private external fun netUrlConnectionHeaderAt(handle: Long, index: Int): String?

@KsSymbolName("__kk_net_url_connection_header_key_at")
private external fun netUrlConnectionHeaderKeyAt(handle: Long, index: Int): String?

@KsSymbolName("__kk_net_url_connection_headers_map")
private external fun netUrlConnectionHeadersMap(handle: Long): String

@KsSymbolName("__kk_net_url_connection_response_code")
private external fun netUrlConnectionResponseCode(handle: Long): Int

@KsSymbolName("__kk_net_url_connection_response_message")
private external fun netUrlConnectionResponseMessage(handle: Long): String?

@KsSymbolName("__kk_net_url_connection_disconnect")
private external fun netUrlConnectionDisconnect(handle: Long)
