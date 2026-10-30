import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.InputStream
import java.io.InputStreamReader
import java.io.OutputStream

fun useJavaCloseable(value: java.io.Closeable) {
    value.close()
    println("java.io.Closeable")
}

fun useJavaAutoCloseable(value: java.lang.AutoCloseable) {
    value.close()
    println("java.lang.AutoCloseable")
}

fun main() {
    val dataInput = DataInputStream("abc".byteInputStream())
    val input: InputStream = dataInput
    println(input.read())
    println(input.read())
    println(input.read())

    val bytes = ByteArrayOutputStream()
    val dataOutput = DataOutputStream(bytes)
    val output: OutputStream = dataOutput
    output.write(65)
    output.write(byteArrayOf(66, 67))
    output.flush()
    val result = bytes.toByteArray()
    println(result.size)
    println(result[0])
    println(result[1])
    println(result[2])

    useJavaCloseable("io".byteInputStream())
    useJavaAutoCloseable("auto".byteInputStream())
    useJavaCloseable("reader".byteInputStream().bufferedReader())
    useJavaAutoCloseable(ByteArrayOutputStream().bufferedWriter())
    useJavaCloseable(InputStreamReader("reader".byteInputStream()))
    useJavaAutoCloseable(BufferedReader(InputStreamReader("nested".byteInputStream())))
}
