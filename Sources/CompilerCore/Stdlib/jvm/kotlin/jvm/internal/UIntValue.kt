package kotlin.jvm.internal
@kotlin.jvm.JvmInline
value class UIntValue(val data: Int): Comparable<UIntValue> {
    override fun compareTo(other: UIntValue): Int = __jvmUIntCompare(data, other.data)
    override fun toString(): String = __jvmUIntString(data)
}
