import RuntimeABI

/// Array lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
struct ArrayLookupNames {
    let arrayOfName: InternedString
    let emptyArrayName: InternedString
    let intArrayOfName: InternedString
    let longArrayOfName: InternedString
    let shortArrayOfName: InternedString
    let byteArrayOfName: InternedString
    let ubyteArrayOfName: InternedString
    let ushortArrayOfName: InternedString
    let uintArrayOfName: InternedString
    let ulongArrayOfName: InternedString
    let doubleArrayOfName: InternedString
    let floatArrayOfName: InternedString
    let booleanArrayOfName: InternedString
    let charArrayOfName: InternedString
    let kkEmptyArrayName: InternedString
    let kkArraySizeName: InternedString
    let kkArrayNewName: InternedString
    let kkArraySetName: InternedString
    // Array conversion / utility ABI names (STDLIB-087/089)
    let kkArrayToListName: InternedString
    let kkArrayCopyOfName: InternedString
    let kkListAsSequenceName: InternedString
    let kkArrayAsSequenceName: InternedString
    let kkArrayOfName: InternedString
    let arrayOfFactoryNames: Set<InternedString>

    init(interner: StringInterner) {
        arrayOfName = interner.intern("arrayOf")
        emptyArrayName = interner.intern("emptyArray")
        intArrayOfName = interner.intern("intArrayOf")
        longArrayOfName = interner.intern("longArrayOf")
        shortArrayOfName = interner.intern("shortArrayOf")
        byteArrayOfName = interner.intern("byteArrayOf")
        ubyteArrayOfName = interner.intern("ubyteArrayOf")
        ushortArrayOfName = interner.intern("ushortArrayOf")
        uintArrayOfName = interner.intern("uintArrayOf")
        ulongArrayOfName = interner.intern("ulongArrayOf")
        doubleArrayOfName = interner.intern("doubleArrayOf")
        floatArrayOfName = interner.intern("floatArrayOf")
        booleanArrayOfName = interner.intern("booleanArrayOf")
        charArrayOfName = interner.intern("charArrayOf")
        kkEmptyArrayName = interner.intern("kk_empty_array")
        kkArraySizeName = interner.intern("__kk_array_size")
        kkArrayNewName = interner.intern("kk_array_new")
        kkArraySetName = interner.intern("kk_array_set")
        kkArrayToListName = interner.intern("__kk_array_toList")
        kkArrayCopyOfName = interner.intern("__kk_array_copyOf")
        kkListAsSequenceName = interner.intern("kk_list_asSequence")
        kkArrayAsSequenceName = interner.intern("kk_array_asSequence")
        kkArrayOfName = interner.intern("kk_array_of")
        arrayOfFactoryNames = [arrayOfName, emptyArrayName, intArrayOfName, longArrayOfName, shortArrayOfName, byteArrayOfName, ubyteArrayOfName, ushortArrayOfName, uintArrayOfName, ulongArrayOfName, doubleArrayOfName, floatArrayOfName, booleanArrayOfName, charArrayOfName]
    }
}
