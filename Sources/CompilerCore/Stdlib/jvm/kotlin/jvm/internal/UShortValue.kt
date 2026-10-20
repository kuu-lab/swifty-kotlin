package kotlin.jvm.internal
@kotlin.jvm.JvmInline
value class UShortValue(val data: Short): Comparable<UShortValue> {
    override fun compareTo(other: UShortValue): Int = (data.toInt() and 65535).compareTo(other.data.toInt() and 65535)
    override fun toString(): String = (data.toInt() and 65535).toString()
}
