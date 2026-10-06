/// Interned name tables backing `trackedStaticTypeKind` (LOWERING-001).
///
/// Every probed name and package prefix is compilation-constant, so the pass
/// builds this table once via `CollectionLiteralLookupTables` instead of
/// re-interning the stdlib names and re-allocating per-kind name arrays on
/// every classified expression.
struct StaticTypeClassificationNames {
    /// One dictionary probe replaces the ordered per-kind
    /// `simpleNames.contains` scans `trackedStaticTypeKind` used to run.
    struct Entry {
        let kind: CollectionLiteralTrackedStaticTypeKind
        /// Package prefix the symbol's FQ name must sit under.
        let package: [InternedString]
    }

    /// Tracked stdlib simple name → classification. The names are unique
    /// across categories, so this map is equivalent to the ordered per-kind
    /// name lists it replaces.
    let trackedKindBySimpleName: [InternedString: Entry]

    /// Receiver FQ names confirmed to construct a fresh source Sequence
    /// object — see `isKnownSourceObjectConstructingAsSequenceReceiver`.
    let sourceObjectConstructingAsSequenceReceivers: Set<[InternedString]>

    init(interner: StringInterner) {
        let kotlinPackage = [interner.intern("kotlin")]
        let collectionsPackage = kotlinPackage + [interner.intern("collections")]
        let sequencesPackage = kotlinPackage + [interner.intern("sequences")]

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
