package kotlin.io

import java.io.InputStream
import kotlin.jvm.internal.__jvmByteArrayOutputStream
import kotlin.jvm.internal.__jvmInputStreamAvailable
import kotlin.jvm.internal.__jvmInputStreamRead
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
