package java.net

/** Abstract base for protocol-agnostic socket addresses. */
public abstract class SocketAddress {
    public constructor()
}

/** An IP socket address (hostname or [InetAddress] plus port). Resolution is
 * eager, matching the JDK: constructing with a hostname resolves it now;
 * [createUnresolved] keeps an unresolved endpoint. */
public open class InetSocketAddress : SocketAddress {
    public var address: InetAddress?
    private var hostname: String?
    public var port: Int
        private set

    public constructor(port: Int) {
        inetSocketCheckPort(port)
        this.port = port
        this.address = InetAddress("0.0.0.0", "0.0.0.0")
        this.hostname = null
    }

    public constructor(addr: InetAddress?, port: Int) {
        inetSocketCheckPort(port)
        this.port = port
        this.address = addr ?: InetAddress("0.0.0.0", "0.0.0.0")
        this.hostname = addr?.hostName?.ifEmpty { null }
    }

    public constructor(hostname: String?, port: Int) {
        inetSocketCheckPort(port)
        this.port = port
        if (hostname == null) {
            this.address = InetAddress("0.0.0.0", "0.0.0.0")
            this.hostname = null
        } else {
            val resolved = InetAddress.getByName(hostname)
            this.address = resolved
            this.hostname = hostname
        }
    }

    private constructor(hostname: String, port: Int, unresolved: Boolean) {
        if (!unresolved) throw IllegalArgumentException()
        this.port = port
        this.address = null
        this.hostname = hostname
    }

    /** The resolved [InetAddress] or `null` when unresolved. */
    public fun getAddress(): InetAddress? = address

    /** The hostname, or the address' hostname when constructed with a literal. */
    public val hostName: String
        get() {
            val addrHost = address?.hostName
            return hostname ?: (if (addrHost.isNullOrEmpty()) address?.hostAddress ?: "" else addrHost ?: "")
        }


    /** The hostname if one was supplied, otherwise the literal address string. */
    public val hostString: String
        get() = hostname ?: address?.hostAddress ?: ""



    /** `true` when this endpoint was created via [createUnresolved]. */
    public val isUnresolved: Boolean
        get() = address == null


    override fun equals(other: Any?): Boolean {
        if (other !is InetSocketAddress) return false
        if (port != other.port || isUnresolved != other.isUnresolved) return false
        if (isUnresolved) return hostname == other.hostname
        return address == other.address
    }

    override fun hashCode(): Int =
        if (isUnresolved) (hostname ?: "").hashCode() + port else 31 * (address?.hashCode() ?: 0) + port

    override fun toString(): String =
        if (isUnresolved) "$hostname/<unresolved>:$port" else "${address.toString()}:$port"

    public companion object {
        public fun createUnresolved(host: String, port: Int): InetSocketAddress {
            inetSocketCheckPort(port)
            return InetSocketAddress(host, port, true)
        }
    }
}

private fun inetSocketCheckPort(port: Int) {
    if (port < 0 || port > 0xFFFF) throw IllegalArgumentException("port out of range:$port")
}
