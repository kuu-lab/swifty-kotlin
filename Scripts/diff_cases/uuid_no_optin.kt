import java.nio.ByteBuffer
import java.util.UUID
import kotlin.uuid.Uuid
import kotlin.uuid.getUuid
import kotlin.uuid.putUuid
import kotlin.uuid.toJavaUuid
import kotlin.uuid.toKotlinUuid

// kotlin.uuid.Uuid's core API is stable since Kotlin 2.4.x: none of the usages
// below may require @OptIn(kotlin.uuid.ExperimentalUuidApi::class).
// generateV4/generateV7/generateV7NonMonotonicAt/LEXICAL_ORDER stay experimental
// upstream and are intentionally not exercised here.
fun main() {
    val u = Uuid.parse("550e8400-e29b-41d4-a716-446655440000")
    println(u.toString())
    println(u.toHexString())
    println(u.toHexDashString())
    println(Uuid.parseOrNull("550e8400-e29b-41d4-a716-446655440000") == u)
    println(Uuid.parseHex("550e8400e29b41d4a716446655440000") == u)
    println(Uuid.parseHexOrNull("550e8400e29b41d4a716446655440000") == u)
    println(Uuid.parseHexDash("550e8400-e29b-41d4-a716-446655440000") == u)
    println(Uuid.parseHexDashOrNull("550e8400-e29b-41d4-a716-446655440000") == u)
    println(Uuid.NIL)
    println(Uuid.SIZE_BITS)
    println(Uuid.SIZE_BYTES)
    println(Uuid.fromLongs(0x550e8400e29b41d4L, 0xa716446655440000uL.toLong()) == u)
    println(Uuid.fromByteArray(u.toByteArray()) == u)
    u.toLongs { msb, lsb ->
        println(msb == 0x550e8400e29b41d4L)
        println(lsb == 0xa716446655440000uL.toLong())
    }
    println(Uuid.random().toString().length == 36)
    println(Uuid.random() != Uuid.random())
    println(u.compareTo(Uuid.NIL) > 0)
    println(u.hashCode() == Uuid.parse("550e8400-e29b-41d4-a716-446655440000").hashCode())

    val ju = UUID(0x550e8400e29b41d4L, 0xa716446655440000uL.toLong())
    println(ju.toKotlinUuid() == u)
    println(u.toJavaUuid() == ju)

    val buf = ByteBuffer.allocate(16)
    buf.putUuid(u)
    println(buf.getUuid(0) == u)
}
