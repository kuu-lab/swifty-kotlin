@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class, kotlinx.serialization.SealedSerializationApi::class)

import kotlinx.serialization.descriptors.*

class MutableChild(private val original: SerialDescriptor) : SerialDescriptor by original {
    var hash: Int = 17
    override fun hashCode(): Int = hash
}

fun expectCollectionFailure(message: String, action: () -> Any?) {
    try { action(); error("missing failure") }
    catch (e: IllegalArgumentException) { check(e.message == message) }
}

fun main() {
    val key = PrimitiveSerialDescriptor("custom.Key", PrimitiveKind.INT)
    val value = PrimitiveSerialDescriptor("custom.Value", PrimitiveKind.STRING).nullable
    val list = listSerialDescriptor(key)
    val set = setSerialDescriptor(key)
    check(list.serialName == "kotlin.collections.ArrayList")
    check(set.serialName == "kotlin.collections.HashSet")
    check(list == listSerialDescriptor(PrimitiveSerialDescriptor("custom.Key", PrimitiveKind.INT)))
    check(set == setSerialDescriptor(key) && list != set && set != list)
    check(list != listSerialDescriptor(value) && !list.equals(null) && !list.equals("list"))
    for (descriptor in listOf(list, set)) {
        check(descriptor.kind === StructureKind.LIST && descriptor.elementsCount == 1)
        check(!descriptor.isNullable && !descriptor.isInline && descriptor.annotations.isEmpty())
        check(descriptor.hashCode() == key.hashCode() * 31 + descriptor.serialName.hashCode())
        check(descriptor.toString() == "${descriptor.serialName}($key)")
        for (index in listOf(0, 1, 2, 3, Int.MAX_VALUE)) {
            check(descriptor.getElementName(index) == index.toString())
            check(descriptor.getElementIndex(index.toString()) == index)
            check(descriptor.getElementDescriptor(index) === key)
            check(descriptor.getElementAnnotations(index).isEmpty() && !descriptor.isElementOptional(index))
        }
        for (index in listOf(-1, Int.MIN_VALUE)) {
            check(descriptor.getElementName(index) == index.toString())
            check(descriptor.getElementIndex(index.toString()) == index)
            val message = "Illegal index $index, ${descriptor.serialName} expects only non-negative indices"
            expectCollectionFailure(message) { descriptor.getElementDescriptor(index) }
            expectCollectionFailure(message) { descriptor.getElementAnnotations(index) }
            expectCollectionFailure(message) { descriptor.isElementOptional(index) }
        }
        check(descriptor.getElementIndex("+001") == 1 && descriptor.getElementIndex("-0") == 0)
        for (name in listOf("", " 1", "1 ", "1.0", "2147483648", "-2147483649", "+", "-")) {
            expectCollectionFailure("$name is not a valid list index") { descriptor.getElementIndex(name) }
        }
    }
    println("list-set:unbounded-indices:${list.hashCode()}:${set.hashCode()}")

    val map = mapSerialDescriptor(key, value)
    check(map.serialName == "kotlin.collections.HashMap")
    check(map.kind === StructureKind.MAP && map.elementsCount == 2)
    check(!map.isNullable && !map.isInline && map.annotations.isEmpty())
    check(map == mapSerialDescriptor(key, value) && map != mapSerialDescriptor(value, key))
    check(!map.equals(null) && !map.equals(list))
    check(map.hashCode() == (map.serialName.hashCode() * 31 + key.hashCode()) * 31 + value.hashCode())
    check(map.toString() == "kotlin.collections.HashMap($key, $value)")
    for (index in listOf(0, 1, 2, 3, Int.MAX_VALUE)) {
        check(map.getElementName(index) == index.toString() && map.getElementIndex(index.toString()) == index)
        check(map.getElementDescriptor(index) === if (index % 2 == 0) key else value)
        check(map.getElementAnnotations(index).isEmpty() && !map.isElementOptional(index))
    }
    for (index in listOf(-1, Int.MIN_VALUE)) {
        check(map.getElementName(index) == index.toString() && map.getElementIndex(index.toString()) == index)
        val message = "Illegal index $index, ${map.serialName} expects only non-negative indices"
        expectCollectionFailure(message) { map.getElementDescriptor(index) }
        expectCollectionFailure(message) { map.getElementAnnotations(index) }
        expectCollectionFailure(message) { map.isElementOptional(index) }
    }
    check(map.getElementIndex("+001") == 1 && map.getElementIndex("-0") == 0)
    for (name in listOf("", " 1", "1 ", "1.0", "2147483648", "-2147483649", "+", "-")) {
        expectCollectionFailure("$name is not a valid map index") { map.getElementIndex(name) }
    }
    check(listSerialDescriptor(map).getElementDescriptor(2) === map)
    println("map:alternating-key-value:${map.hashCode()}")

    val mutable = MutableChild(key)
    val liveList = listSerialDescriptor(mutable)
    val liveMap = mapSerialDescriptor(mutable, value)
    val firstListHash = liveList.hashCode()
    val firstMapHash = liveMap.hashCode()
    mutable.hash = Int.MAX_VALUE
    check(liveList.hashCode() != firstListHash && liveMap.hashCode() != firstMapHash)
    check(liveList.hashCode() == Int.MAX_VALUE * 31 + liveList.serialName.hashCode())
    check(liveMap.hashCode() == (liveMap.serialName.hashCode() * 31 + Int.MAX_VALUE) * 31 + value.hashCode())
    check(liveList.getElementDescriptor(Int.MAX_VALUE) === mutable && liveMap.getElementDescriptor(2) === mutable)
    println("hash:live-child:overflow:${liveList.hashCode()}:${liveMap.hashCode()}")
}
