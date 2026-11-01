import java.net.BindException
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.MalformedURLException
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketAddress
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.URL
import java.net.URLConnection
import java.net.URLDecoder
import java.net.URLEncoder
import java.net.UnknownHostException
import java.util.Scanner

fun main() {
    // URL parsing (JVM-consistent field extraction, no network needed).
    val url = URL("https://user:pw@example.com:8443/a/b/c.txt?q=1&r=2#frag")
    println("url ${url.protocol} ${url.authority} ${url.userInfo} ${url.host} ${url.port} ${url.path} ${url.query} ${url.ref}")
    println("file=${url.file} defaultPort=${url.defaultPort} ext=${url.toExternalForm()}")
    val rel = URL(url, "../d/e.txt")
    println("rel=${rel.toExternalForm()}")
    val rel2 = URL(url, "x.png")
    println("rel2=${rel2.toExternalForm()}")
    val abs = URL(url, "/root.txt?z=9")
    println("abs=${abs.toExternalForm()}")
    val file = URL("file:///tmp/some/file.txt")
    println("fileurl ${file.protocol} ${file.path} ${file.host}")

    // openConnection picks the right concrete type per protocol.
    val http = URL("http://example.com/x").openConnection()
    println("conn http=${http is HttpURLConnection} urlconn=${http is URLConnection}")
    val fileConn = file.openConnection()
    println("conn file http=${fileConn is HttpURLConnection}")

    // HttpURLConnection defaults (no connect performed).
    val hconn = URL("https://example.com").openConnection() as HttpURLConnection
    hconn.requestMethod = "POST"
    hconn.connectTimeout = 5000
    hconn.readTimeout = 3000
    println("http method=${hconn.requestMethod} timeouts=${hconn.connectTimeout}/${hconn.readTimeout}")
    println("disconn ok=${try { hconn.disconnect(); 1 } catch (e: Throwable) { 0 }}")

    // URLConnection option properties.
    val c = URL("http://example.com").openConnection()
    c.doInput = true
    c.doOutput = false
    c.useCaches = false
    c.setRequestProperty("X-Test", "yes")
    println("props ${c.doInput}/${c.doOutput}/${c.useCaches} req=${c.getRequestProperty("X-Test")}")

    // Percent coding.
    val enc = URLEncoder.encode("a b+c&d=e/f")
    println("enc=$enc dec=${URLDecoder.decode(enc)}")
    println("enc2=${URLEncoder.encode("héllo", "UTF-8")}")
    println("dec2=${URLDecoder.decode("a+b%2Bc%26d", "UTF-8")}")
    println("decode-raw=${URLDecoder.decode("%41%42%43")}")

    // InetAddress value behavior (loopback/literals only — resolver independent).
    val loop = InetAddress.getLoopbackAddress()
    println("loop ${loop.hostAddress} ${loop.hostName} lb=${loop.isLoopbackAddress} v4=${!loop.hostAddress.contains(':')}")
    val literal = InetAddress.getByName("127.0.0.1")
    println("literal ${literal.hostAddress} lb=${literal.isLoopbackAddress}")
    val v6 = InetAddress.getByName("::1")
    println("v6 ${v6.hostAddress} lb=${v6.isLoopbackAddress} v4=${!v6.hostAddress.contains(':')}")
    val b = InetAddress.getByAddress(byteArrayOf(192.toByte(), 168.toByte(), 1, 7))
    println("byaddr=${b.hostAddress}")
    println("addr bytes=${loop.getAddress().size}")

    // Socket addresses.
    val sa = InetSocketAddress("localhost", 8080)
    println("sa ${sa.hostString}:${sa.port} unresolved=${sa.isUnresolved}")
    val sa2 = InetSocketAddress(InetAddress.getLoopbackAddress(), 9090)
    println("sa2 ${sa2.hostName}:${sa2.port} unresolved=${sa2.isUnresolved} addr=${sa2.address?.hostAddress}")
    val sa3 = InetSocketAddress.createUnresolved("never-resolved.invalid", 1)
    println("sa3 unresolved=${sa3.isUnresolved}")
    val base: SocketAddress = sa2
    println("sockaddr=${base is InetSocketAddress}")

    // Loopback TCP echo — deterministic, exercises Socket/ServerSocket/streams.
    val server = ServerSocket(0)
    val serverPort = server.localPort
    println("server bound=${server.isBound} port>0=${serverPort > 0} local=${server.localSocketAddress is InetSocketAddress}")
    val client = Socket("127.0.0.1", serverPort)
    println("client conn=${client.isConnected} bound=${client.isBound} inet=${client.inetAddress?.hostAddress} port=${client.port == serverPort}")
    val accepted = server.accept()
    println("accepted conn=${accepted.isConnected}")
    client.outputStream.write("ping".toByteArray())
    client.outputStream.flush()
    val buf = ByteArray(16)
    val n = accepted.inputStream.read(buf)
    println("echo=${buf.decodeToString(0, n)}")
    accepted.outputStream.write("pong".toByteArray())
    accepted.outputStream.flush()
    val buf2 = ByteArray(16)
    val n2 = client.inputStream.read(buf2)
    println("echo2=${buf2.decodeToString(0, n2)}")
    // Scanner over a socket InputStream exercises the new Scanner ctor.
    val echoServer = ServerSocket(0)
    val c2 = Socket("127.0.0.1", echoServer.localPort)
    val a2 = echoServer.accept()
    a2.outputStream.write("line one\nline two\n".toByteArray())
    a2.outputStream.flush()
    val sc = Scanner(c2.inputStream)
    println("scan1=${sc.nextLine()}")
    println("scan2=${sc.nextLine()}")
    // Socket options round-trip.
    client.tcpNoDelay = true
    client.keepAlive = true
    client.soTimeout = 1500
    println("opts nodelay=${client.tcpNoDelay} keepalive=${client.keepAlive} timeout=${client.soTimeout}")
    println("bufs snd>0=${client.sendBufferSize > 0} rcv>0=${client.receiveBufferSize > 0}")
    client.shutdownInput()
    client.shutdownOutput()
    println("shutdown in=${client.isInputShutdown} out=${client.isOutputShutdown}")
    client.close()
    accepted.close()
    c2.close()
    a2.close()
    echoServer.close()
    server.close()
    println("closed client=${client.isClosed} server=${server.isClosed}")
    println("strings client=${client.toString().startsWith("Socket[")} server=${server.toString().startsWith("ServerSocket[")}")
    // Exception hierarchy sanity.
    println("exc ${UnknownHostException("x") is java.io.IOException} ${ConnectException("x") is SocketException} ${BindException("x") is SocketException} ${SocketTimeoutException("x").message} ${MalformedURLException("m").message}")
}
