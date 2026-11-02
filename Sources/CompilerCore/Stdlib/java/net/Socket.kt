package java.net

import java.io.Closeable
import java.io.InputStream
import java.io.OutputStream
import kotlin.internal.KsSymbolName

/** Native source-backed `java.net.Socket`: a real TCP client socket backed by
 * POSIX sockets in the runtime. All traffic goes through
 * `socket`/`connect`/`send`/`recv` on the kernel descriptor, so the observable
 * behavior (bytes, timeouts, errors) matches the JDK. */
public open class Socket : Closeable {
    private var handle: Long
    private var closed = false

    /** Creates an unconnected socket. */
    public constructor() {
        handle = netSocketCreate()
    }

    /** Creates a socket and connects it to `host`:`port`.
     * @throws UnknownHostException if `host` cannot be resolved
     * @throws ConnectException if the connection is refused or times out */
    public constructor(host: String, port: Int) : this() {
        connect(InetSocketAddress(host, port), 0)
    }

    public constructor(address: InetAddress, port: Int) : this() {
        connect(InetSocketAddress(address, port), 0)
    }

    /** Wraps a runtime-owned connected handle (accepted sockets). */
    internal constructor(rawHandle: Long) {
        handle = rawHandle
    }

    /** Connects this socket to `endpoint`, optionally with a timeout in
     * milliseconds (`0` = block forever). */
    public open fun connect(endpoint: SocketAddress) {
        connect(endpoint, 0)
    }

    public open fun connect(endpoint: SocketAddress, timeout: Int) {
        if (timeout < 0) throw IllegalArgumentException("negative timeout")
        if (endpoint !is InetSocketAddress) {
            throw IllegalArgumentException("Unsupported address type")
        }
        if (closed) throw SocketException("Socket is closed")
        val resolved = endpoint.getAddress()
            ?: throw UnknownHostException(endpoint.hostName)
        netSocketConnect(handle, resolved.hostAddress, endpoint.port, timeout)
    }

    /** Binds the socket to a local address before connecting. */
    public open fun bind(bindpoint: SocketAddress) {
        if (closed) throw SocketException("Socket is closed")
        if (bindpoint !is InetSocketAddress) {
            throw IllegalArgumentException("Unsupported address type")
        }
        val resolved = bindpoint.getAddress()
            ?: throw UnknownHostException(bindpoint.hostName)
        netSocketBind(handle, resolved.hostAddress, bindpoint.port)
    }

    public val inputStream: InputStream get() = getInputStream()
    public val outputStream: OutputStream get() = getOutputStream()

    public open fun getInputStream(): InputStream = netSocketInputStream(handle)

    public open fun getOutputStream(): OutputStream = netSocketOutputStream(handle)

    public val isConnected: Boolean
        get() = !closed && netSocketIsConnected(handle)


    public val isBound: Boolean
        get() = netSocketIsBound(handle)


    public val isClosed: Boolean
        get() = closed || netSocketIsClosed(handle)


    override fun close() {
        if (closed) return
        closed = true
        netSocketClose(handle)
    }

    public val inetAddress: InetAddress?
        get() = netSocketRemoteAddress(handle)?.let { InetAddress.fromNumeric(it) }


    public val port: Int
        get() = netSocketRemotePort(handle)


    public val localPort: Int
        get() = netSocketLocalPort(handle)


    public val localAddress: InetAddress?
        get() = netSocketLocalAddress(handle)?.let { InetAddress.fromNumeric(it) }


    public val remoteSocketAddress: SocketAddress? get() = getRemoteSocketAddress()
    public val localSocketAddress: SocketAddress? get() = getLocalSocketAddress()

    public fun getRemoteSocketAddress(): SocketAddress? {
        val remote = inetAddress ?: return null
        return InetSocketAddress(remote, port)
    }

    public fun getLocalSocketAddress(): SocketAddress? {
        val local = localAddress ?: return null
        return InetSocketAddress(local, localPort)
    }

    public var soTimeout: Int
        get() = netSocketGetOption(handle, SO_TIMEOUT)
        set(value) {
            if (value < 0) throw IllegalArgumentException("timeout < 0")
            netSocketSetOption(handle, SO_TIMEOUT, value)
        }


    public var tcpNoDelay: Boolean
        get() = netSocketGetOption(handle, TCP_NODELAY) != 0
        set(value) = netSocketSetOption(handle, TCP_NODELAY, if (value) 1 else 0)


    public var keepAlive: Boolean
        get() = netSocketGetOption(handle, SO_KEEPALIVE) != 0
        set(value) = netSocketSetOption(handle, SO_KEEPALIVE, if (value) 1 else 0)


    public var reuseAddress: Boolean
        get() = netSocketGetOption(handle, SO_REUSEADDR) != 0
        set(value) = netSocketSetOption(handle, SO_REUSEADDR, if (value) 1 else 0)


    public var sendBufferSize: Int
        get() = netSocketGetOption(handle, SO_SNDBUF)
        set(value) = netSocketSetOption(handle, SO_SNDBUF, value)


    public var receiveBufferSize: Int
        get() = netSocketGetOption(handle, SO_RCVBUF)
        set(value) = netSocketSetOption(handle, SO_RCVBUF, value)


    public fun shutdownInput() = netSocketShutdown(handle, shutdownRead)

    public fun shutdownOutput() = netSocketShutdown(handle, shutdownWrite)

    public val isInputShutdown: Boolean
        get() = netSocketIsInputShutdown(handle)


    public val isOutputShutdown: Boolean
        get() = netSocketIsOutputShutdown(handle)


    override fun toString(): String {
        if (!isConnected) return "Socket[unconnected]"
        return "Socket[addr=$inetAddress,port=$port,localport=$localPort]"
    }

    private companion object {
        private const val SO_TIMEOUT = 0
        private const val SO_REUSEADDR = 1
        private const val SO_KEEPALIVE = 2
        private const val TCP_NODELAY = 3
        private const val SO_SNDBUF = 4
        private const val SO_RCVBUF = 5
        private const val shutdownRead = 0
        private const val shutdownWrite = 1
    }
}

@KsSymbolName("__kk_net_socket_create")
private external fun netSocketCreate(): Long

@KsSymbolName("__kk_net_socket_connect")
private external fun netSocketConnect(handle: Long, numericHost: String, port: Int, timeoutMillis: Int)

@KsSymbolName("__kk_net_socket_bind")
private external fun netSocketBind(handle: Long, numericHost: String, port: Int)

@KsSymbolName("__kk_net_socket_input_stream")
private external fun netSocketInputStream(handle: Long): InputStream

@KsSymbolName("__kk_net_socket_output_stream")
private external fun netSocketOutputStream(handle: Long): OutputStream

@KsSymbolName("__kk_net_socket_close")
private external fun netSocketClose(handle: Long)

@KsSymbolName("__kk_net_socket_is_closed")
private external fun netSocketIsClosed(handle: Long): Boolean

@KsSymbolName("__kk_net_socket_is_connected")
private external fun netSocketIsConnected(handle: Long): Boolean

@KsSymbolName("__kk_net_socket_is_bound")
private external fun netSocketIsBound(handle: Long): Boolean

/** The peer's numeric address, or `null` when unconnected. */
@KsSymbolName("__kk_net_socket_remote_address")
private external fun netSocketRemoteAddress(handle: Long): String?

@KsSymbolName("__kk_net_socket_remote_port")
private external fun netSocketRemotePort(handle: Long): Int

@KsSymbolName("__kk_net_socket_local_address")
private external fun netSocketLocalAddress(handle: Long): String?

@KsSymbolName("__kk_net_socket_local_port")
private external fun netSocketLocalPort(handle: Long): Int

@KsSymbolName("__kk_net_socket_get_option")
private external fun netSocketGetOption(handle: Long, option: Int): Int

@KsSymbolName("__kk_net_socket_set_option")
private external fun netSocketSetOption(handle: Long, option: Int, value: Int)

@KsSymbolName("__kk_net_socket_shutdown")
private external fun netSocketShutdown(handle: Long, how: Int)

@KsSymbolName("__kk_net_socket_is_input_shutdown")
private external fun netSocketIsInputShutdown(handle: Long): Boolean

@KsSymbolName("__kk_net_socket_is_output_shutdown")
private external fun netSocketIsOutputShutdown(handle: Long): Boolean
