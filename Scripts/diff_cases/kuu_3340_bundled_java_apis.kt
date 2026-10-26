import java.security.MessageDigest
import java.util.Base64
import java.util.Comparator
import java.util.EnumMap
import java.util.EnumSet
import java.util.Objects
import java.util.Scanner
import java.util.StringJoiner
import java.util.zip.CRC32

enum class Kuu3340Kind { FIRST, SECOND, THIRD }

fun hex(bytes: ByteArray): String = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }

fun main() {
    val scanner = Scanner("alpha beta")
    println(scanner.next())
    println(scanner.next())
    println(scanner.hasNext())

    println(StringJoiner(",", "[", "]").add("a").add("b"))

    val enumMap = EnumMap<Kuu3340Kind, Int>(Kuu3340Kind::class.java)
    enumMap[Kuu3340Kind.THIRD] = 3
    enumMap[Kuu3340Kind.FIRST] = 1
    println(enumMap.keys.joinToString(","))

    println(EnumSet.of(Kuu3340Kind.THIRD, Kuu3340Kind.FIRST).joinToString(","))
    println(EnumSet.allOf(Kuu3340Kind::class.java).joinToString(","))
    println(EnumSet.copyOf(EnumSet.of(Kuu3340Kind.SECOND)).joinToString(","))
    println(EnumSet.complementOf(EnumSet.of(Kuu3340Kind.SECOND)).joinToString(","))
    println(EnumSet.range(Kuu3340Kind.FIRST, Kuu3340Kind.SECOND).joinToString(","))

    val encoded = Base64.getEncoder().encodeToString("hello".encodeToByteArray())
    println(encoded)
    println(Base64.getDecoder().decode(encoded).decodeToString())
    println(Base64.getDecoder().decode("aGVsbG8").decodeToString())
    println(Base64.getUrlDecoder().decode("Pj4-").decodeToString())

    val checksum = CRC32()
    checksum.update("123456789".encodeToByteArray())
    println(checksum.getValue())

    println(hex(MessageDigest.getInstance("MD5").digest("test".encodeToByteArray())))

    val value: Any = "x"
    println(value is Cloneable)

    val comparator = Comparator<Int> { left, right -> left.compareTo(right) }
    println(Objects.compare(1, 2, comparator))
}
