package kotlin.jvm.internal
class ShortSpreadBuilder(initialSize: Int): PrimitiveSpreadBuilder<ShortArray>(initialSize) {
    private val values = ShortArray(initialSize)
    protected override fun getSize(value: ShortArray): Int = value.size
    fun add(value: Short) { values[position++] = value }
    fun toArray(): ShortArray = toArray(values, ShortArray(size()))
}
