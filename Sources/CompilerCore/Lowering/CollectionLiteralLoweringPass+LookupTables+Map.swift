import RuntimeABI

/// Map lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
struct MapLookupNames {
    let mapOfName: InternedString
    let mutableMapOfName: InternedString
    let hashMapOfName: InternedString
    let linkedMapOfName: InternedString
    let emptyMapName: InternedString
    let hashMapName: InternedString
    let linkedHashMapName: InternedString
    let kkEmptyMapName: InternedString
    let kkMapOfName: InternedString
    let kkMapSizeName: InternedString
    let kkMapGetName: InternedString
    let kkMapIsEmptyName: InternedString
    let kkMapForEachName: InternedString
    let kkMapMapName: InternedString
    let kkMapFilterName: InternedString
    let kkMapFilterKeysName: InternedString
    let kkMapFilterValuesName: InternedString
    let kkMapMapValuesName: InternedString
    let kkMapMapKeysName: InternedString
    let kkMapCountName: InternedString
    let kkMapAnyName: InternedString
    let kkMapAllName: InternedString
    let kkMapNoneName: InternedString
    let kkMapFlatMapName: InternedString
    let kkMapMaxByOrNullName: InternedString
    let kkMapMinByOrNullName: InternedString
    let kkMapToStringName: InternedString
    let kkMapIteratorName: InternedString
    let kkMapIteratorHasNextName: InternedString
    let kkMapIteratorNextName: InternedString
    let kkMutableMapPutAllName: InternedString
    let mapFactoryNames: Set<InternedString>
    let mutableMapConstructorNames: Set<InternedString>

    init(interner: StringInterner) {
        mapOfName = interner.intern("mapOf")
        mutableMapOfName = interner.intern("mutableMapOf")
        hashMapOfName = interner.intern("hashMapOf")
        linkedMapOfName = interner.intern("linkedMapOf")
        emptyMapName = interner.intern("emptyMap")
        hashMapName = interner.intern("HashMap")
        linkedHashMapName = interner.intern("LinkedHashMap")
        kkEmptyMapName = interner.intern("__kk_emptyMap")
        kkMapOfName = interner.intern("__kk_map_of")
        kkMapSizeName = interner.intern("kk_map_size")
        kkMapGetName = interner.intern("__kk_map_get")
        kkMapIsEmptyName = interner.intern("kk_map_is_empty")
        kkMapForEachName = interner.intern("kk_map_forEach")
        kkMapMapName = interner.intern("kk_map_map")
        kkMapFilterName = interner.intern("kk_map_filter")
        kkMapFilterKeysName = interner.intern("kk_map_filterKeys")
        kkMapFilterValuesName = interner.intern("kk_map_filterValues")
        kkMapMapValuesName = interner.intern("kk_map_mapValues")
        kkMapMapKeysName = interner.intern("kk_map_mapKeys")
        kkMapCountName = interner.intern("kk_map_count")
        kkMapAnyName = interner.intern("kk_map_any")
        kkMapAllName = interner.intern("kk_map_all")
        kkMapNoneName = interner.intern("kk_map_none")
        kkMapFlatMapName = interner.intern("kk_map_flatMap")
        kkMapMaxByOrNullName = interner.intern("kk_map_maxByOrNull")
        kkMapMinByOrNullName = interner.intern("kk_map_minByOrNull")
        kkMapToStringName = interner.intern("kk_map_to_string")
        kkMapIteratorName = interner.intern("__kk_map_iterator")
        kkMapIteratorHasNextName = interner.intern("__kk_map_iterator_hasNext")
        kkMapIteratorNextName = interner.intern("__kk_map_iterator_next")
        kkMutableMapPutAllName = interner.intern("kk_mutable_map_putAll")
        mapFactoryNames = [mapOfName, mutableMapOfName, hashMapOfName, linkedMapOfName, emptyMapName]
        mutableMapConstructorNames = [hashMapName, linkedHashMapName]
    }
}
