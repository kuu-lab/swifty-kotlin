package java.net

import kotlin.internal.KsSymbolName

/** Native source-backed compatibility type for JVM-shaped `java.net.InetAddress`
 * signatures. Name resolution delegates to the platform resolver (`getaddrinfo`)
 * through the runtime, so results match the system resolver including
 * `/etc/hosts` overrides. Addresses are carried in their JVM textual form
 * (dotted-quad IPv4, uncompressed eight-group IPv6). */
public open class InetAddress internal constructor(
    private val host: String,
    private val numericAddress: String
) {
    /** The host name this address was created with, or the empty string. */
    public val hostName: String
        get() = host

    /** The raw IP address in textual (numeric) form. */
    public val hostAddress: String
        get() = numericAddress



    public fun getAddress(): ByteArray = inetAddressToBytes(numericAddress)

    /** `true` when this is the IPv4 wildcard `0.0.0.0` or the IPv6 `::` wildcard. */
    public val isAnyLocalAddress: Boolean
        get() = numericAddress == "0.0.0.0" || numericAddress == "0:0:0:0:0:0:0:0"

    /** `true` for IPv4 `127/8` or IPv6 `::1`. */
    public val isLoopbackAddress: Boolean
        get() = numericAddress.startsWith("127.") || numericAddress == "0:0:0:0:0:0:0:1"

    /** `true` for IPv4 `169.254/16` or IPv6 `fe80::/10`. */
    public val isLinkLocalAddress: Boolean
        get() = numericAddress.startsWith("169.254.") || inetAddressV6GroupRange(numericAddress, 0xfe80, 0xfebf)

    /** `true` for IPv4 site-local `10/8`, `172.16/12`, `192.168/16`
     * or IPv6 `fec0::/10` site-local. */
    public val isSiteLocalAddress: Boolean
        get() = numericAddress.startsWith("10.") ||
            numericAddress.startsWith("192.168.") ||
            inetAddressV4SecondOctetIn(numericAddress, 172, 16, 31) ||
            inetAddressV6GroupRange(numericAddress, 0xfec0, 0xfeff)

    /** `true` for IPv4 `224/4` multicast or IPv6 `ff00::/8` multicast. */
    public val isMulticastAddress: Boolean
        get() = inetAddressV4FirstOctetIn(numericAddress, 224, 239) ||
            inetAddressV6GroupRange(numericAddress, 0xff00, 0xffff)

    /** `true` when the numeric form has no `:` — i.e. it is a dotted-quad
     * IPv4 literal. (JDK-compat helper name kept for source compatibility.) */
    public val isIPv4Address: Boolean
        get() = !numericAddress.contains(':')

    override fun equals(other: Any?): Boolean =
        other is InetAddress && numericAddress == other.numericAddress

    override fun hashCode(): Int = numericAddress.hashCode()

    override fun toString(): String = "$host/$numericAddress"

    public companion object {
        /** Resolves `host` through the platform resolver. `null`/empty resolves
         * to the loopback address, matching the JDK. Throws
         * [UnknownHostException] when resolution fails. */
        public fun getByName(host: String?): InetAddress {
            if (host == null || host.isEmpty()) return getLoopbackAddress()
            val addresses = netResolveAddresses(host)
            val first = addresses[0]
            // The JDK reports a reverse-resolved name for literal inputs and the
            // given name otherwise; fall back to the literal when PTR lookup fails.
            val name = if (inetAddressIsNumericLiteral(host)) {
                netReverseLookup(first) ?: host
            } else {
                host
            }
            return InetAddress(name, first)
        }

        public fun getAllByName(host: String?): Array<InetAddress> {
            if (host == null || host.isEmpty()) return arrayOf(getLoopbackAddress())
            val addresses = netResolveAddresses(host)
            val name = if (inetAddressIsNumericLiteral(host)) {
                netReverseLookup(addresses[0]) ?: host
            } else {
                host
            }
            return Array(addresses.size) { InetAddress(name, addresses[it]) }
        }

        public fun getByAddress(addr: ByteArray): InetAddress =
            InetAddress("", inetAddressFormat(addr))

        public fun getByAddress(host: String?, addr: ByteArray): InetAddress =
            InetAddress(host ?: "", inetAddressFormat(addr))

        /** The host name of the local machine resolved to an address, matching
         * the JDK `getLocalHost` behavior. */
        public fun getLocalHost(): InetAddress {
            val name = netLocalHostName()
            val addresses = try {
                netResolveAddresses(name)
            } catch (_: UnknownHostException) {
                return InetAddress(name, "127.0.0.1")
            }
            return InetAddress(name, addresses[0])
        }

        public fun getLoopbackAddress(): InetAddress = InetAddress("localhost", "127.0.0.1")

        internal fun fromNumeric(address: String): InetAddress = InetAddress("", address)
    }
}

private fun inetAddressIsNumericLiteral(host: String): Boolean {
    if (host.isEmpty()) return false
    if (host.all { it.isDigit() || it == '.' }) return true
    return host.contains(':')
}

private fun inetAddressV4FirstOctetIn(address: String, low: Int, high: Int): Boolean {
    val dot = address.indexOf('.')
    if (dot <= 0) return false
    val first = address.substring(0, dot).toIntOrNull() ?: return false
    return first in low..high
}

private fun inetAddressV4SecondOctetIn(address: String, firstOctet: Int, low: Int, high: Int): Boolean {
    val firstDot = address.indexOf('.')
    if (firstDot <= 0) return false
    val rest = address.substring(firstDot + 1)
    val secondDot = rest.indexOf('.')
    if (secondDot <= 0) return false
    if (address.substring(0, firstDot).toIntOrNull() != firstOctet) return false
    val second = rest.substring(0, secondDot).toIntOrNull() ?: return false
    return second in low..high
}

private fun inetAddressV6GroupRange(address: String, lowFirst: Int, highFirst: Int): Boolean {
    if (!address.contains(':')) return false
    val firstGroup = address.substringBefore(':').toIntOrNull(16) ?: return false
    return firstGroup in lowFirst..highFirst
}

private fun inetAddressToBytes(address: String): ByteArray {
    if (!address.contains(':')) {
        val parts = address.split('.')
        if (parts.size != 4) return ByteArray(0)
        return ByteArray(4) { (parts[it].toIntOrNull() ?: 0).toByte() }
    }
    val groups = address.split(':')
    val result = ByteArray(16)
    var index = 0
    for (group in groups) {
        val value = group.toIntOrNull(16) ?: 0
        result[index] = (value shr 8).toByte()
        result[index + 1] = (value and 0xff).toByte()
        index += 2
    }
    return result
}

private fun inetAddressFormat(addr: ByteArray): String {
    if (addr.size == 4) {
        return (0..3).joinToString(".") { (addr[it].toInt() and 0xff).toString() }
    }
    if (addr.size == 16) {
        // The JDK models `::ffff:a.b.c.d` as an Inet4Address and prints the
        // dotted-quad form.
        val mapped = (0 until 10).all { addr[it].toInt() == 0 } &&
            addr[10].toInt() == -1 && addr[11].toInt() == -1
        if (mapped) {
            return (12..15).joinToString(".") { (addr[it].toInt() and 0xff).toString() }
        }
        return (0 until 8).joinToString(":") {
            val group = ((addr[it * 2].toInt() and 0xff) shl 8) or (addr[it * 2 + 1].toInt() and 0xff)
            group.toString(16)
        }
    }
    throw IllegalArgumentException("Invalid address length: ${addr.size}")
}

/** Space-separated numeric addresses for `host` in resolver order, or throws
 * `java.net.UnknownHostException` via the thrown slot. */
@KsSymbolName("__kk_net_resolve")
private external fun netResolveRaw(host: String): String

/** PTR-record lookup; returns an empty string when the record is absent. */
@KsSymbolName("__kk_net_reverse_lookup")
private external fun netReverseLookupRaw(address: String): String

@KsSymbolName("__kk_net_local_host_name")
private external fun netLocalHostName(): String

private fun netResolveAddresses(host: String): List<String> {
    val raw = netResolveRaw(host)
    // The JDK prefers IPv4 results unless java.net.preferIPv6Addresses is set.
    return raw.split(' ').filter { it.isNotEmpty() }
        .sortedBy { if (it.contains('.')) 0 else 1 }
}

private fun netReverseLookup(address: String): String? {
    val name = netReverseLookupRaw(address)
    return name.ifEmpty { null }
}
