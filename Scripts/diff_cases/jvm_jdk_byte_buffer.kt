// DIFF_JVM
import java.nio.ByteBuffer
fun main() { val b = ByteBuffer.allocate(4); b.putInt(42); b.flip(); println(b.int) }
