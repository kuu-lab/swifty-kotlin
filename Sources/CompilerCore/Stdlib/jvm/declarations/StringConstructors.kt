package kotlin

// Top-level `String(...)` constructor shims. On the JVM backend they bind to
// the matching java.lang.String <init> descriptors (see prepareTextLibrary).
fun String(chars: CharArray): String = null!!
fun String(chars: CharArray, offset: Int, length: Int): String = null!!
fun String(codePoints: IntArray, offset: Int, count: Int): String = null!!
fun String(bytes: ByteArray): String = null!!
fun String(bytes: ByteArray, charset: kotlin.text.Charset): String = null!!
fun String(bytes: ByteArray, offset: Int, length: Int, charset: kotlin.text.Charset): String = null!!
