package kotlin.jvm.internal
class FloatSpreadBuilder(initialSize: Int): PrimitiveSpreadBuilder<FloatArray>(initialSize) {
    private val values = FloatArray(initialSize)
    protected override fun getSize(value: FloatArray): Int = value.size
    fun add(value: Float) { values[position++] = value }
    fun toArray(): FloatArray = toArray(values, FloatArray(size()))
}
