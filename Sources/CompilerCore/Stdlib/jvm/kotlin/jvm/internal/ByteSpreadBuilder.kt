package kotlin.jvm.internal
class ByteSpreadBuilder(initialSize: Int): PrimitiveSpreadBuilder<ByteArray>(initialSize) {
    private val values = ByteArray(initialSize)
    protected override fun getSize(value: ByteArray): Int = value.size
    fun add(value: Byte) { values[position++] = value }
    fun toArray(): ByteArray = toArray(values, ByteArray(size()))
}
