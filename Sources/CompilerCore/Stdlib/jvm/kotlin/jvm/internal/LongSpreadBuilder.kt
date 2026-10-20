package kotlin.jvm.internal
class LongSpreadBuilder(initialSize: Int): PrimitiveSpreadBuilder<LongArray>(initialSize) {
    private val values = LongArray(initialSize)
    protected override fun getSize(value: LongArray): Int = value.size
    fun add(value: Long) { values[position++] = value }
    fun toArray(): LongArray = toArray(values, LongArray(size()))
}
