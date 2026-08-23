// KSP-953: source-backed Collection/Map/Array ifEmpty overloads.

class CustomCollection : AbstractCollection<String?>() {
    override val size: Int get() = 1
    override fun iterator(): Iterator<String?> = emptyList<String?>().iterator()
}

class EmptyCustomCollection : AbstractCollection<String?>() {
    override val size: Int get() = 0
    override fun iterator(): Iterator<String?> = emptyList<String?>().iterator()
}

class CustomMap : Map<String?, Int?> by mapOf<String?, Int?>("key" to 1) {
    override val size: Int get() = 1
}

class EmptyCustomMap : Map<String?, Int?> by emptyMap<String?, Int?>() {
    override val size: Int get() = 0
}

fun collectionIsEmpty(value: Collection<String?>): Boolean = value.isEmpty()
fun mapIsEmpty(value: Map<String?, Int?>): Boolean = value.isEmpty()

fun main() {
    var fallbackCalls = 0

    val listIsEmpty = listOf(1).isEmpty()
    println(listIsEmpty)

    val nonEmptyCollection: Collection<String?> = listOf(null)
    val collectionIdentity: Any? = nonEmptyCollection.ifEmpty {
        fallbackCalls += 1
        "unexpected-collection-fallback"
    }
    println(collectionIdentity === nonEmptyCollection)

    val emptyCollection: Collection<String?> = emptyList()
    println(emptyCollection.ifEmpty {
        fallbackCalls += 1
        "collection-fallback"
    })

    val nonEmptyMap: Map<String?, Int?> = mapOf<String?, Int?>("key" to 1)
    val mapIdentity: Any? = nonEmptyMap.ifEmpty {
        fallbackCalls += 1
        "unexpected-map-fallback"
    }
    println(mapIdentity === nonEmptyMap)

    val emptyMap: Map<String?, Int?> = emptyMap()
    println(emptyMap.ifEmpty {
        fallbackCalls += 1
        "map-fallback"
    })

    val nonEmptyArray: Array<String?> = arrayOf(null)
    val arrayIdentity: Any? = nonEmptyArray.ifEmpty {
        fallbackCalls += 1
        "unexpected-array-fallback"
    }
    println(arrayIdentity === nonEmptyArray)

    val emptyArray: Array<String?> = emptyArray()
    println(emptyArray.ifEmpty {
        fallbackCalls += 1
        "array-fallback"
    })

    val customCollection = CustomCollection()
    println(customCollection.ifEmpty {
        fallbackCalls += 1
        "unexpected-custom-collection-fallback"
    } === customCollection)

    val customMap = CustomMap()
    println(customMap.ifEmpty {
        fallbackCalls += 1
        "unexpected-custom-map-fallback"
    } === customMap)

    println(collectionIsEmpty(customCollection))
    println(collectionIsEmpty(EmptyCustomCollection()))
    println(mapIsEmpty(customMap))
    println(mapIsEmpty(EmptyCustomMap()))

    println(fallbackCalls)
}
