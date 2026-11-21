struct StaticTypeClassificationNames {
    struct Entry {
        let kind: CollectionLiteralTrackedStaticTypeKind
        let package: [InternedString]
    }

    let trackedKindBySimpleName: [InternedString: Entry]

    let sourceObjectConstructingAsSequenceReceivers: Set<[InternedString]>

    init(interner: StringInterner) {
        let kotlinPackage = [interner.intern("kotlin")]
        let collectionsPackage = kotlinPackage + [interner.intern("collections")]
        let sequencesPackage = kotlinPackage + [interner.intern("sequences")]
        let javaUtilPackage = [interner.intern("java"), interner.intern("util")]

        var byName: [InternedString: Entry] = [:]
        for name in [
            "List", "MutableList", "ArrayList", "AbstractList", "AbstractMutableList",
        ] {
            byName[interner.intern(name)] = Entry(kind: .list, package: collectionsPackage)
        }
        for name in [
            "Set", "MutableSet", "HashSet", "LinkedHashSet", "AbstractSet", "AbstractMutableSet",
        ] {
            byName[interner.intern(name)] = Entry(kind: .set, package: collectionsPackage)
        }
        for name in [
            "Map", "MutableMap", "HashMap", "LinkedHashMap", "AbstractMap", "AbstractMutableMap",
        ] {
            byName[interner.intern(name)] = Entry(kind: .map, package: collectionsPackage)
        }
        for name in ["SortedSet", "NavigableSet", "TreeSet"] {
            byName[interner.intern(name)] = Entry(kind: .set, package: javaUtilPackage)
        }
        for name in ["SortedMap", "NavigableMap", "TreeMap"] {
            byName[interner.intern(name)] = Entry(kind: .map, package: javaUtilPackage)
        }
        for name in [
            "Array", "IntArray", "LongArray", "DoubleArray", "FloatArray",
            "BooleanArray", "CharArray", "ByteArray", "ShortArray",
            "UByteArray", "UShortArray", "UIntArray", "ULongArray",
        ] {
            byName[interner.intern(name)] = Entry(kind: .array, package: kotlinPackage)
        }
        byName[interner.intern("Sequence")] = Entry(kind: .sequence, package: sequencesPackage)
        byName[interner.intern("String")] = Entry(kind: .string, package: kotlinPackage)
        trackedKindBySimpleName = byName

        sourceObjectConstructingAsSequenceReceivers = [
            collectionsPackage + [interner.intern("Iterable")],
            collectionsPackage + [interner.intern("Iterator")],
            collectionsPackage + [interner.intern("Map")],
            kotlinPackage + [interner.intern("CharSequence")],
        ]
    }
}
