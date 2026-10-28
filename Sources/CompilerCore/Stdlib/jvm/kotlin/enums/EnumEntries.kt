@file:kotlin.jvm.JvmName("EnumEntriesKt")
package kotlin.enums
import kotlin.jvm.internal.__jvmEnumEntries
interface EnumEntries<E: Enum<E>>: List<E>, kotlin.jvm.internal.markers.KMappedMarker
fun <E: Enum<E>> enumEntries(entries: Array<E>): EnumEntries<E> = __jvmEnumEntries(entries)
