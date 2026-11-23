package kotlin.io

import java.io.InputStream
import java.io.InputStreamReader
import java.io.Reader
import java.nio.charset.Charset
import kotlin.jvm.internal.__jvmByteArrayOutputStream
import kotlin.jvm.internal.__jvmInputStreamAvailable
import kotlin.jvm.internal.__jvmInputStreamRead
import kotlin.jvm.internal.__jvmInputStreamReader
import kotlin.jvm.internal.__jvmReaderRead
import kotlin.jvm.internal.__jvmOutputStreamToBytes
import kotlin.jvm.internal.__jvmOutputStreamWrite

public fun InputStream.readBytes(): ByteArray {
    val buffer = ByteArray(8192)
    val output = __jvmByteArrayOutputStream(maxOf(buffer.size, __jvmInputStreamAvailable(this)))
    var count = __jvmInputStreamRead(this, buffer)
    while (count >= 0) {
        __jvmOutputStreamWrite(output, buffer, 0, count)
        count = __jvmInputStreamRead(this, buffer)
    }
    return __jvmOutputStreamToBytes(output)
}

public fun InputStream.reader(charset: Charset = Charsets.UTF_8): InputStreamReader =
    __jvmInputStreamReader(this, charset)

public fun Reader.readText(): String {
    val buffer = CharArray(8192)
    val result = StringBuilder()
    var count = __jvmReaderRead(this, buffer)
    while (count >= 0) {
        result.append(buffer, 0, count)
        count = __jvmReaderRead(this, buffer)
    }
    return result.toString()
}
