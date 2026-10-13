import design_patterns.*
fun main() {
    println(HttpConnectionClient1.Builder().dnsServerAddress("1.1.1.1").callTimeout(100).build())
    println(HttpConnectionClient2.newBuilder().dnsServerAddress("1.1.1.1").callTimeout(100).build())
    println(HttpConnectionClient3(dnsServerAddress = "1.1.1.1", callTimeout = 100))
}
