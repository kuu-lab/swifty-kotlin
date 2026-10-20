package kotlin.jvm.internal
@kotlin.jvm.JvmInline
value class UByteValue(val data: Byte): Comparable<UByteValue> {
    override fun compareTo(other: UByteValue): Int = (data.toInt() and 255).compareTo(other.data.toInt() and 255)
    override fun toString(): String = (data.toInt() and 255).toString()
}
