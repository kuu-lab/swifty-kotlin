package kotlin.jvm.internal
@kotlin.jvm.JvmInline
value class ULongValue(val data: Long): Comparable<ULongValue> {
    override fun compareTo(other: ULongValue): Int = __jvmULongCompare(data, other.data)
    override fun toString(): String = __jvmULongString(data)
}
