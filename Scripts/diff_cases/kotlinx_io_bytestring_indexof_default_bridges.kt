import kotlinx.io.bytestring.ByteString
import kotlinx.io.bytestring.indexOf

fun main() {
    val subject = ByteString(byteArrayOf(1, 2, 3, 2, 3))

    println(subject.indexOf(2.toByte()))
    println(subject.indexOf(byteArrayOf(3, 2)))
    println(subject.indexOf(ByteString(byteArrayOf(2, 3))))
    println(subject.indexOf(9.toByte()))
    println(subject.indexOf(byteArrayOf(3, 4)))
    println(subject.indexOf(ByteString(byteArrayOf())))
    println(subject.indexOf(byteArrayOf()))
}
