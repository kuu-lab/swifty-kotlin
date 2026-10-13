package kotlin.io

import java.io.InputStream
import java.io.OutputStream
import java.io.ByteArrayInputStream
import java.io.BufferedReader
import java.io.BufferedWriter
import java.nio.charset.Charset
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_input_stream_bufferedReader")
private external fun InputStream.bufferedReaderWithTag(charsetTag: Int): BufferedReader

@KsSymbolName("__kk_output_stream_bufferedWriter")
private external fun OutputStream.bufferedWriterWithTag(charsetTag: Int): BufferedWriter

public fun InputStream.bufferedReader(charset: Charset = Charsets.UTF_8): BufferedReader =
    bufferedReaderWithTag(charset.tag)

public fun OutputStream.bufferedWriter(charset: Charset = Charsets.UTF_8): BufferedWriter =
    bufferedWriterWithTag(charset.tag)

public fun String.byteInputStream(charset: Charset): ByteArrayInputStream =
    toByteArray(charset).inputStream()

public fun java.io.ByteArrayOutputStream.toString(charset: Charset): String = toByteArray().toString(charset)

public fun java.io.ByteArrayOutputStream.toString(charsetName: String): String {
    val charset = try { Charset.forName(charsetName) } catch (_: IllegalArgumentException) {
        throw java.io.UnsupportedEncodingException(charsetName)
    }
    return toByteArray().toString(charset)
}
