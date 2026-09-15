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
    let kkHashMapOfName: InternedString
    let kkLinkedHashMapOfName: InternedString
    let kkMapSizeName: InternedString
    let kkMapGetName: InternedString
    let kkMapIsEmptyName: InternedString
    let kkMapCountName: InternedString
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
        kkHashMapOfName = interner.intern("__kk_hash_map_of")
        kkLinkedHashMapOfName = interner.intern("__kk_linked_hash_map_of")
        kkMapSizeName = interner.intern("kk_map_size")
        kkMapGetName = interner.intern("__kk_map_get")
        kkMapIsEmptyName = interner.intern("kk_map_is_empty")
        kkMapCountName = interner.intern("kk_map_count")
        kkMapToStringName = interner.intern("kk_map_to_string")
        kkMapIteratorName = interner.intern("__kk_map_iterator")
        kkMapIteratorHasNextName = interner.intern("__kk_map_iterator_hasNext")
        kkMapIteratorNextName = interner.intern("__kk_map_iterator_next")
        kkMutableMapPutAllName = interner.intern("__kk_mutable_map_putAll")
        mapFactoryNames = [mapOfName, mutableMapOfName, hashMapOfName, linkedMapOfName, emptyMapName]
        mutableMapConstructorNames = [hashMapName, linkedHashMapName]
    }
}
