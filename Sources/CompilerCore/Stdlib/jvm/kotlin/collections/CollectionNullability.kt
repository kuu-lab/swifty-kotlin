@file:kotlin.jvm.JvmName("CollectionsKt")
package kotlin.collections

import kotlin.contracts.contract

@kotlin.internal.InlineOnly
inline fun <T> List<T>?.orEmpty(): List<T> = this ?: emptyList<T>()

@kotlin.internal.InlineOnly
inline fun <T> Collection<T>?.orEmpty(): Collection<T> = this ?: emptyList<T>()

@kotlin.internal.InlineOnly
public inline fun <T> Collection<T>?.isNullOrEmpty(): Boolean {
    contract {
        returns(false) implies (this != null)
    }
    val value = this
    if (value == null) return true
    return value.isEmpty()
}
