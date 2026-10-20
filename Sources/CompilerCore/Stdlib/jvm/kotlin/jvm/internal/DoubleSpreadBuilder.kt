package kotlin.jvm.internal
class DoubleSpreadBuilder(initialSize: Int): PrimitiveSpreadBuilder<DoubleArray>(initialSize) {
    private val values = DoubleArray(initialSize)
    protected override fun getSize(value: DoubleArray): Int = value.size
    fun add(value: Double) { values[position++] = value }
    fun toArray(): DoubleArray = toArray(values, DoubleArray(size()))
}
