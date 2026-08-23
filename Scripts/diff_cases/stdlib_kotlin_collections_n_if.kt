// KSP-953: collection/map/array ifEmpty parity and lazy fallback evaluation.

class CustomCollection : AbstractCollection<String?>() {
    override val size: Int get() = 1
    override fun iterator(): Iterator<String?> = emptyList<String?>().iterator()
}

class CustomMap : Map<String?, Int?> by mapOf<String?, Int?>("key" to 1) {
    override val size: Int get() = 1
}

fun main() {
    var fallbackCalls = 0

    val nonEmptyCollection: Collection<String?> = listOf(null)
    val collectionIdentity: Any? = nonEmptyCollection.ifEmpty {
        fallbackCalls += 1
        "unexpected-collection-fallback"
    }
    println(collectionIdentity === nonEmptyCollection)

    val emptyCollection: Collection<String?> = emptyList()
    val collectionFallback: Any? = emptyCollection.ifEmpty {
        fallbackCalls += 1
        "collection-fallback"
    }
    println(collectionFallback)

    val nonEmptyMap: Map<String?, Int?> = mapOf<String?, Int?>("key" to 1)
    val mapIdentity: Any? = nonEmptyMap.ifEmpty {
        fallbackCalls += 1
        "unexpected-map-fallback"
    }
    println(mapIdentity === nonEmptyMap)

    val emptyMap: Map<String?, Int?> = emptyMap()
    val mapFallback: Any? = emptyMap.ifEmpty {
        fallbackCalls += 1
        "map-fallback"
    }
    println(mapFallback)

    val nonEmptyArray: Array<String?> = arrayOf(null)
    val arrayIdentity: Any? = nonEmptyArray.ifEmpty {
        fallbackCalls += 1
        "unexpected-array-fallback"
    }
    println(arrayIdentity === nonEmptyArray)

    val emptyArray: Array<String?> = emptyArray()
    val arrayFallback: Any? = emptyArray.ifEmpty {
        fallbackCalls += 1
        "array-fallback"
    }
    println(arrayFallback)

    val customCollection = CustomCollection()
    val customCollectionIdentity: Any? = customCollection.ifEmpty {
        fallbackCalls += 1
        "unexpected-custom-collection-fallback"
    }
    println(customCollectionIdentity === customCollection)

    val customMap = CustomMap()
    val customMapIdentity: Any? = customMap.ifEmpty {
        fallbackCalls += 1
        "unexpected-custom-map-fallback"
    }
    println(customMapIdentity === customMap)

    println(fallbackCalls)
}
