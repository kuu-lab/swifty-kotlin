package kotlin.jvm.internal
class BooleanSpreadBuilder(initialSize: Int): PrimitiveSpreadBuilder<BooleanArray>(initialSize) {
    private val values = BooleanArray(initialSize)
    protected override fun getSize(value: BooleanArray): Int = value.size
    fun add(value: Boolean) { values[position++] = value }
    fun toArray(): BooleanArray = toArray(values, BooleanArray(size()))
}
