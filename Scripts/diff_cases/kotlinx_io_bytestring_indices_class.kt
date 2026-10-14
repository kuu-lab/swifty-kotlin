import kotlinx.io.bytestring.ByteString
import kotlinx.io.bytestring.indices

fun name(value: Any): String? = value::class.simpleName

fun main() {
    // KUU-1822 ledger klib-8eb9402560ac1395 observes indices through Any.
    val indices: Any = ByteString(1, 2, 3).indices
    println("value:other:" + name(indices))
    println(indices::class.qualifiedName)
    println(indices::class === IntRange::class)
    val empty: Any = ByteString().indices
    println("value:other:" + name(empty))
    println(empty::class === IntRange::class)
}
