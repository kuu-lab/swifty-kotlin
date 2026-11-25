@file:kotlin.jvm.JvmName("StringsKt")

package kotlin.text

private object CaseInsensitiveOrder : Comparator<String> {
    override fun compare(left: String, right: String): Int = left.compareTo(right, ignoreCase = true)
}

public fun getCASE_INSENSITIVE_ORDER(receiver: kotlin.jvm.internal.StringCompanionObject): Comparator<String> =
    CaseInsensitiveOrder
