package java.net

import java.io.Closeable
import kotlin.internal.KsSymbolName

/** Native source-backed `java.net.ServerSocket`: a real TCP listening socket
 * backed by POSIX `bind`/`listen`/`accept`. [accept] returns real connected
 * [Socket] instances; [setSoTimeout] bounds the accept wait like the JDK. */
public open class ServerSocket : Closeable {
    private var handle: Long
    private var closed = false

    /** Creates an unbound server socket. */
    public constructor() {
        handle = netServerSocketCreate()
    }

    /** Creates a server socket bound to the wildcard address on `port`
     * (`0` = any free port). */
    public constructor(port: Int) : this() {
        checkServerPort(port)
        bind(InetSocketAddress(port))
    }

    public constructor(port: Int, backlog: Int) : this() {
        checkServerPort(port)
        bind(InetSocketAddress(port), backlog)
    }

    public constructor(port: Int, backlog: Int, bindAddr: InetAddress?) : this() {
        checkServerPort(port)
        bind(InetSocketAddress(bindAddr, port), backlog)
    }

    public open fun bind(endpoint: SocketAddress) {
        bind(endpoint, 50)
    }

    public open fun bind(endpoint: SocketAddress, backlog: Int) {
        if (closed) throw SocketException("Socket is closed")
        if (endpoint !is InetSocketAddress) {
            throw IllegalArgumentException("Unsupported address type")
        }
        val resolved = endpoint.getAddress()
            ?: throw UnknownHostException(endpoint.hostName)
        netServerSocketBind(handle, resolved.hostAddress, endpoint.port, backlog)
    }

    /** Blocks until a connection arrives and returns its [Socket].
     * @throws SocketTimeoutException when [setSoTimeout] elapses first. */
    public open fun accept(): Socket {
        val client = netServerSocketAccept(handle)
        return Socket(client)
    }

    public val isBound: Boolean
        get() = netServerSocketIsBound(handle)


    public val isClosed: Boolean
        get() = closed || netServerSocketIsClosed(handle)


    override fun close() {
        if (closed) return
        closed = true
        netServerSocketClose(handle)
    }

    public val localPort: Int
        get() = netServerSocketLocalPort(handle)


    public val inetAddress: InetAddress?
        get() = netServerSocketLocalAddress(handle)?.let { InetAddress.fromNumeric(it) }


    public val localSocketAddress: SocketAddress? get() = getLocalSocketAddress()

    public fun getLocalSocketAddress(): SocketAddress? {
        val local = inetAddress ?: return null
        return InetSocketAddress(local, localPort)
    }

    public var soTimeout: Int
        get() = netServerSocketGetTimeout(handle)
        set(value) {
            if (value < 0) throw IllegalArgumentException("negative timeout")
            netServerSocketSetTimeout(handle, value)
        }


    public var reuseAddress: Boolean
        get() = netServerSocketReuseAddress(handle) != 0
        set(value) = netServerSocketSetReuseAddress(handle, if (value) 1 else 0)


    override fun toString(): String {
        if (!isBound) return "ServerSocket[unbound]"
        return "ServerSocket[addr=$inetAddress,localport=$localPort]"
    }
}

private fun checkServerPort(port: Int) {
    if (port < 0 || port > 0xFFFF) throw IllegalArgumentException("Port value out of range: $port")
}

@KsSymbolName("__kk_net_server_socket_create")
private external fun netServerSocketCreate(): Long

@KsSymbolName("__kk_net_server_socket_bind")
private external fun netServerSocketBind(handle: Long, numericHost: String, port: Int, backlog: Int)

@KsSymbolName("__kk_net_server_socket_accept")
private external fun netServerSocketAccept(handle: Long): Long

@KsSymbolName("__kk_net_server_socket_close")
private external fun netServerSocketClose(handle: Long)

@KsSymbolName("__kk_net_server_socket_is_closed")
private external fun netServerSocketIsClosed(handle: Long): Boolean

@KsSymbolName("__kk_net_server_socket_is_bound")
private external fun netServerSocketIsBound(handle: Long): Boolean

@KsSymbolName("__kk_net_server_socket_local_port")
private external fun netServerSocketLocalPort(handle: Long): Int

@KsSymbolName("__kk_net_server_socket_local_address")
private external fun netServerSocketLocalAddress(handle: Long): String?

@KsSymbolName("__kk_net_server_socket_get_timeout")
private external fun netServerSocketGetTimeout(handle: Long): Int

@KsSymbolName("__kk_net_server_socket_set_timeout")
private external fun netServerSocketSetTimeout(handle: Long, timeoutMillis: Int)

@KsSymbolName("__kk_net_server_socket_get_reuse_address")
private external fun netServerSocketReuseAddress(handle: Long): Int

@KsSymbolName("__kk_net_server_socket_set_reuse_address")
private external fun netServerSocketSetReuseAddress(handle: Long, value: Int)
