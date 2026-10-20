package kotlin.jvm.internal
class CharSpreadBuilder(initialSize: Int): PrimitiveSpreadBuilder<CharArray>(initialSize) {
    private val values = CharArray(initialSize)
    protected override fun getSize(value: CharArray): Int = value.size
    fun add(value: Char) { values[position++] = value }
    fun toArray(): CharArray = toArray(values, CharArray(size()))
}
