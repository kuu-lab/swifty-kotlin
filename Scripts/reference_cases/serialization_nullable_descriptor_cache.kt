@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class, kotlinx.serialization.SealedSerializationApi::class)

package kotlinx.serialization.internal

import kotlinx.serialization.descriptors.*

internal class CachedDescriptor : SerialDescriptor by PrimitiveSerialDescriptor("custom.Cached", PrimitiveKind.STRING), CachedNames {
    override val serialNames: Set<String> = setOf("cached", "other")
    override val elementsCount: Int get() = 2
    override fun getElementName(index: Int): String = error("cached names must not be read")
}

internal class FallbackDescriptor : SerialDescriptor by PrimitiveSerialDescriptor("custom.Fallback", PrimitiveKind.INT) {
    override val elementsCount: Int get() = 2
    var currentName: String = "shared"
    var reads: Int = 0
    override fun getElementName(index: Int): String {
        reads++
        return currentName
    }
}

fun main() {
    val cached = CachedDescriptor()
    check(cached.cachedSerialNames() === cached.serialNames)
    val fast = SerialDescriptorForNullable(cached)
    check(fast.original === cached && fast.serialNames === cached.serialNames)
    check(fast.cachedSerialNames() === cached.serialNames)
    check(fast.serialNames.size == 2 && "cached" in fast.serialNames && "other" in fast.serialNames)
    println("fast-path:same-set:no-name-reads")

    val original = FallbackDescriptor()
    val snapshot = SerialDescriptorForNullable(original)
    check(original.reads == 2 && snapshot.serialNames.size == 1 && "shared" in snapshot.serialNames)
    val firstSet = snapshot.serialNames
    check(snapshot.cachedSerialNames() === firstSet && original.reads == 2)
    original.currentName = "changed"
    check(snapshot.serialNames === firstSet && "shared" in firstSet && "changed" !in firstSet)
    check(original.reads == 2)
    val changed = SerialDescriptorForNullable(original)
    check(original.reads == 4 && changed.serialNames.size == 1 && "changed" in changed.serialNames)
    check(changed.serialNames !== firstSet && snapshot == changed)
    println("fallback:deduplicated:stable-snapshot")
}
