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
    let uintArrayOfName: InternedString
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
    let kkArrayToMutableListName: InternedString

    let kkArrayCopyOfName: InternedString
    let kkArrayCopyOfNewSizeName: InternedString
    let kkArrayCopyOfNewSizeInitName: InternedString
    let kkArrayCopyOfRangeName: InternedString
    let kkArrayFillName: InternedString
    let kkListAsSequenceName: InternedString
    let kkArrayAsSequenceName: InternedString
    let kkArrayOfName: InternedString
    // Array member names (STDLIB-087/088/089)
    let toMutableListName: InternedString
    let toTypedArrayName: InternedString
    let copyOfName: InternedString
    let copyOfRangeName: InternedString
    let fillName: InternedString
    let arrayOfFactoryNames: Set<InternedString>

    init(interner: StringInterner) {
        arrayOfName = interner.intern("arrayOf")
        emptyArrayName = interner.intern("emptyArray")
        intArrayOfName = interner.intern("intArrayOf")
        longArrayOfName = interner.intern("longArrayOf")
        shortArrayOfName = interner.intern("shortArrayOf")
        byteArrayOfName = interner.intern("byteArrayOf")
        uintArrayOfName = interner.intern("uintArrayOf")
        doubleArrayOfName = interner.intern("doubleArrayOf")
        floatArrayOfName = interner.intern("floatArrayOf")
        booleanArrayOfName = interner.intern("booleanArrayOf")
        charArrayOfName = interner.intern("charArrayOf")
        kkEmptyArrayName = interner.intern("kk_empty_array")
        kkArraySizeName = interner.intern("kk_array_size")
        kkArrayNewName = interner.intern("kk_array_new")
        kkArraySetName = interner.intern("kk_array_set")
        kkArrayToListName = interner.intern("kk_array_toList")
        kkArrayToMutableListName = interner.intern("kk_array_toMutableList")

        kkArrayCopyOfName = interner.intern("kk_array_copyOf")
        kkArrayCopyOfNewSizeName = interner.intern("kk_array_copyOf_newSize")
        kkArrayCopyOfNewSizeInitName = interner.intern("kk_array_copyOf_newSize_init")
        kkArrayCopyOfRangeName = interner.intern("kk_array_copyOfRange")
        kkArrayFillName = interner.intern("kk_array_fill")
        kkListAsSequenceName = interner.intern("kk_list_asSequence")
        kkArrayAsSequenceName = interner.intern("kk_array_asSequence")
        kkArrayOfName = interner.intern("kk_array_of")
        toMutableListName = interner.intern("toMutableList")
        toTypedArrayName = interner.intern("toTypedArray")
        copyOfName = interner.intern("copyOf")
        copyOfRangeName = interner.intern("copyOfRange")
        fillName = interner.intern("fill")
        arrayOfFactoryNames = [arrayOfName, emptyArrayName, intArrayOfName, longArrayOfName, shortArrayOfName, byteArrayOfName, uintArrayOfName, doubleArrayOfName, floatArrayOfName, booleanArrayOfName, charArrayOfName]
    }
}
