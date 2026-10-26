// DIFF_CANDIDATE_ONLY
// KUU-3463: java.lang.String.getBytes() surface.
// kotlinc-jvm 2.4.20 hides java.lang.String.getBytes from kotlin.String
// resolution, so this case has no JVM reference; the .expected sidecar pins
// the native output (UTF-8 default charset, matching toByteArray()).
fun main() {
    // No-arg getBytes() — UTF-8.
    val ascii = "ab".getBytes()
    println(ascii.size)
    println(ascii.contentToString())

    // Multi-byte UTF-8 content.
    val eAcute = "é".getBytes()
    println(eAcute.size)
    println(eAcute.contentToString())
    println("日本語".getBytes().size)

    // UTF-8 round-trip.
    println("héllo".getBytes().decodeToString())

    // Charset overload.
    println("é".getBytes(Charsets.ISO_8859_1).contentToString())
    println("é".getBytes(Charsets.UTF_8).contentToString())
    println("ab".getBytes(Charsets.UTF_16BE).size)

    // Charset-name overload (java.lang.String.getBytes(String)).
    println("ab".getBytes("UTF-8").size)
    println("é".getBytes("ISO-8859-1").size)
}
