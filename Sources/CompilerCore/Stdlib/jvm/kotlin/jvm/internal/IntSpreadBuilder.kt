package kotlin.jvm.internal
class IntSpreadBuilder(initialSize: Int): PrimitiveSpreadBuilder<IntArray>(initialSize) {
    private val values = IntArray(initialSize)
    protected override fun getSize(value: IntArray): Int = value.size
    fun add(value: Int) { values[position++] = value }
    fun toArray(): IntArray = toArray(values, IntArray(size()))
}
