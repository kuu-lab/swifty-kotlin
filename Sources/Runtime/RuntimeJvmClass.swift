import Foundation

private let runtimeJavaKnownKotlinNominalNames = [
    "kotlin.collections.List",
    "kotlin.collections.MutableList",
    "kotlin.collections.Set",
    "kotlin.collections.MutableSet",
    "kotlin.collections.Map",
    "kotlin.collections.MutableMap",
    "kotlin.collections.Map.Entry",
    "kotlin.collections.MutableMap.MutableEntry",
    "kotlin.collections.ArrayList",
    "kotlin.collections.HashSet",
    "kotlin.collections.LinkedHashSet",
    "kotlin.collections.HashMap",
    "kotlin.collections.LinkedHashMap",
    "kotlin.collections.EmptyList",
    "kotlin.collections.EmptySet",
    "kotlin.collections.EmptyMap",
    "kotlin.Exception",
    "kotlin.RuntimeException",
    "kotlin.IllegalArgumentException",
    "kotlin.IllegalStateException",
    "kotlin.ArithmeticException",
    "kotlin.AssertionError",
    "kotlin.ClassCastException",
    "kotlin.IndexOutOfBoundsException",
    "kotlin.ArrayIndexOutOfBoundsException",
    "kotlin.StringIndexOutOfBoundsException",
    "kotlin.NegativeArraySizeException",
    "kotlin.NullPointerException",
    "kotlin.NumberFormatException",
    "kotlin.UnsupportedOperationException",
    "kotlin.Error",
    "kotlin.OutOfMemoryError",
    "kotlin.StackOverflowError",
    "java.lang.Class",
]

private let runtimeJavaKnownKotlinNominalNameByToken: [Int: String] = {
    var namesByToken: [Int: String] = [:]
    namesByToken.reserveCapacity(runtimeJavaKnownKotlinNominalNames.count)
    for name in runtimeJavaKnownKotlinNominalNames {
        let token = runtimeNominalTypeToken(runtimeStableNominalTypeID(fqName: name))
        if namesByToken[token] == nil {
            namesByToken[token] = name
        }
    }
    return namesByToken
}()

func runtimeJavaClassDisplayText(receiverRaw: Int, typeToken: Int, nameHint: Int) -> String {
    if let arrayName = runtimeJavaArrayClassName(rawValue: receiverRaw) {
        return "class \(arrayName)"
    }

    let metadata = runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)
    let qualifiedName = runtimeJavaQualifiedName(typeToken: typeToken, nameHint: nameHint)

    if let concreteName = runtimeJavaCollectionImplementationName(
        receiverRaw: receiverRaw,
        qualifiedName: qualifiedName
    ) {
        return "class \(concreteName)"
    }

    let binaryName = runtimeJavaBinaryName(qualifiedName, metadataDisplayName: metadata?.displayName)
    let kind = metadata?.isInterface == true
        || runtimeJavaInterfaceNominalNames.contains(qualifiedName)
        ? "interface" : "class"
    return "\(kind) \(binaryName)"
}

func runtimeJavaClassCacheKey(receiverRaw: Int, typeToken: Int, nameHint: Int) -> JavaClassCacheKey {
    if let arrayName = runtimeJavaArrayClassName(rawValue: receiverRaw) {
        let genericArrayToken = runtimeNominalTypeToken(
            runtimeStableNominalTypeID(fqName: "kotlin.Array")
        )
        if typeToken == genericArrayToken {
            return JavaClassCacheKey(typeToken: typeToken, runtimeClassName: arrayName)
        }
    }

    if runtimeListBox(from: receiverRaw) != nil
        || runtimeSetBox(from: receiverRaw) != nil
        || runtimeMapBox(from: receiverRaw) != nil
    {
        let qualifiedName = runtimeJavaQualifiedName(typeToken: typeToken, nameHint: nameHint)
        if let implementationName = runtimeJavaCollectionImplementationName(
            receiverRaw: receiverRaw,
            qualifiedName: qualifiedName
        ) {
            return JavaClassCacheKey(typeToken: typeToken, runtimeClassName: implementationName)
        }
    }

    if let function = runtimeFunctionValueBox(from: receiverRaw) {
        return JavaClassCacheKey(
            typeToken: typeToken,
            functionIdentity: function.fnPtr,
            enclosingClassName: runtimeFunctionEnclosingClassName(for: receiverRaw)
        )
    }

    return JavaClassCacheKey(typeToken: typeToken)
}

func runtimeJavaPrimitiveClassDisplayText(typeToken: Int) -> String {
    return switch Int64(truncatingIfNeeded: typeToken) & RuntimeTypeTokenEncoding.baseMask {
    case RuntimeTypeTokenEncoding.booleanBase: "boolean"
    case RuntimeTypeTokenEncoding.byteBase: "byte"
    case RuntimeTypeTokenEncoding.shortBase: "short"
    case RuntimeTypeTokenEncoding.intBase: "int"
    case RuntimeTypeTokenEncoding.longBase: "long"
    case RuntimeTypeTokenEncoding.charBase: "char"
    case RuntimeTypeTokenEncoding.floatBase: "float"
    case RuntimeTypeTokenEncoding.doubleBase: "double"
    case RuntimeTypeTokenEncoding.nullBase: "void"
    default: "void"
    }
}

func runtimeJavaClassToStringText(_ classRaw: Int) -> String? {
    resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self)?.displayText
}

private func runtimeJavaCollectionImplementationName(receiverRaw: Int, qualifiedName: String) -> String? {
    switch qualifiedName {
    case "kotlin.collections.List", "kotlin.collections.MutableList",
         "kotlin.collections.Set", "kotlin.collections.MutableSet",
         "kotlin.collections.Map", "kotlin.collections.MutableMap",
         "kotlin.collections.Collection", "kotlin.collections.MutableCollection",
         "kotlin.Any", "Unknown":
        break
    default:
        return nil
    }
    guard let typeID = runtimeObjectTypeID(rawValue: receiverRaw) else { return nil }
    switch typeID {
    case arrayListRuntimeTypeID, mutableListRuntimeTypeID:
        return "java.util.ArrayList"
    case singletonListRuntimeTypeID:
        return "java.util.Collections$SingletonList"
    case arraysBackedListRuntimeTypeID:
        return "java.util.Arrays$ArrayList"
    case arrayDequeRuntimeTypeID:
        return "java.util.ArrayDeque"
    case runtimeListBuilderTypeID:
        return "kotlin.collections.builders.ListBuilder"
    case hashSetRuntimeTypeID:
        return "java.util.HashSet"
    case linkedHashSetRuntimeTypeID:
        return "java.util.LinkedHashSet"
    case treeSetRuntimeTypeID:
        return "java.util.TreeSet"
    case runtimeSetBuilderTypeID:
        return "kotlin.collections.builders.SetBuilder"
    case hashMapRuntimeTypeID:
        return "java.util.HashMap"
    case linkedHashMapRuntimeTypeID:
        return "java.util.LinkedHashMap"
    case treeMapRuntimeTypeID, sortedMapRuntimeTypeID, navigableMapRuntimeTypeID:
        return "java.util.TreeMap"
    case mutableMapRuntimeTypeID:
        return "kotlin.collections.builders.MapBuilder"
    default:
        break
    }
    guard let identity = runtimeReflectedCollectionClass(rawValue: receiverRaw, typeID: typeID),
          case let .named(_, reflectedQualifiedName) = identity
    else { return nil }
    return runtimeJavaBinaryName(reflectedQualifiedName, metadataDisplayName: nil)
}

func runtimeJavaQualifiedName(typeToken: Int, nameHint: Int = 0) -> String {
    if let qualifiedName = runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)?.qualifiedName {
        return qualifiedName
    }
    if let name = runtimeJavaKnownKotlinNominalNameByToken[typeToken] {
        return name
    }
    return extractString(from: UnsafeMutableRawPointer(bitPattern: __kk_type_token_qualified_name(typeToken, nameHint)))
        ?? "java.lang.Object"
}

func runtimeJavaBinaryNameForTypeToken(_ typeToken: Int, nameHint: Int = 0) -> String {
    let metadata = runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)
    let qualifiedName = runtimeJavaQualifiedName(typeToken: typeToken, nameHint: nameHint)
    return runtimeJavaBinaryName(qualifiedName, metadataDisplayName: metadata?.displayName)
}

func runtimeJavaBinaryName(_ qualifiedName: String, metadataDisplayName: String?) -> String {
    if runtimeJavaDeeplyNestedImplClassNames.contains(qualifiedName) {
        var binaryName = qualifiedName
        for _ in 0..<2 {
            guard let dot = binaryName.range(of: ".", options: .backwards) else { break }
            binaryName.replaceSubrange(dot, with: "$")
        }
        return binaryName
    }
    if runtimeJavaNestedImplClassNames.contains(qualifiedName),
       let lastDot = qualifiedName.range(of: ".", options: .backwards)
    {
        var binaryName = qualifiedName
        binaryName.replaceSubrange(lastDot, with: "$")
        return binaryName
    }
    return switch qualifiedName {
    case "kotlin.Any": "java.lang.Object"
    case "kotlin.String": "java.lang.String"
    case "kotlin.Boolean": "java.lang.Boolean"
    case "kotlin.Byte": "java.lang.Byte"
    case "kotlin.Short": "java.lang.Short"
    case "kotlin.Int": "java.lang.Integer"
    case "kotlin.Long": "java.lang.Long"
    case "kotlin.Char": "java.lang.Character"
    case "kotlin.Float": "java.lang.Float"
    case "kotlin.Double": "java.lang.Double"
    case "kotlin.Number": "java.lang.Number"
    case "kotlin.Enum": "java.lang.Enum"
    case "kotlin.Cloneable": "java.lang.Cloneable"
    case "kotlin.Comparable": "java.lang.Comparable"
    case "kotlin.CharSequence": "java.lang.CharSequence"
    case "kotlin.Annotation": "java.lang.annotation.Annotation"
    case "kotlin.collections.Collection": "java.util.Collection"
    case "kotlin.collections.List": "java.util.List"
    case "kotlin.collections.MutableList": "java.util.List"
    case "kotlin.collections.Set": "java.util.Set"
    case "kotlin.collections.MutableSet": "java.util.Set"
    case "kotlin.collections.Map": "java.util.Map"
    case "kotlin.collections.MutableMap": "java.util.Map"
    case "kotlin.collections.Map.Entry", "kotlin.collections.MutableMap.MutableEntry": "java.util.Map$Entry"
    case "kotlin.collections.ArrayList": "java.util.ArrayList"
    case "kotlin.collections.HashSet": "java.util.HashSet"
    case "kotlin.collections.LinkedHashSet": "java.util.LinkedHashSet"
    case "kotlin.collections.HashMap": "java.util.HashMap"
    case "kotlin.collections.LinkedHashMap": "java.util.LinkedHashMap"
    case "kotlin.Throwable", "kotlin.RuntimeException", "kotlin.Exception",
         "kotlin.IllegalArgumentException",
         "kotlin.IllegalStateException", "kotlin.ArithmeticException", "kotlin.AssertionError",
         "kotlin.ClassCastException", "kotlin.IndexOutOfBoundsException",
         "kotlin.ArrayIndexOutOfBoundsException", "kotlin.StringIndexOutOfBoundsException",
         "kotlin.NegativeArraySizeException", "kotlin.NullPointerException",
         "kotlin.NumberFormatException", "kotlin.UnsupportedOperationException",
         "kotlin.Error", "kotlin.OutOfMemoryError", "kotlin.StackOverflowError":
        runtimeJVMExceptionFQName(from: qualifiedName)
    default:
        metadataDisplayName ?? qualifiedName
    }
}

private let runtimeJavaNestedImplClassNames: Set<String> = [
    "java.util.Collections.SingletonList",
    "java.util.Collections.SingletonSet",
    "java.util.Collections.SingletonMap",
    "java.util.Arrays.ArrayList",
    "java.util.Arrays.ArrayItr",
    "java.util.AbstractList.SubList",
    "java.util.AbstractList.RandomAccessSubList",
    "java.util.AbstractList.Itr",
    "java.util.AbstractList.ListItr",
    "java.util.AbstractMap.SimpleImmutableEntry",
    "java.util.ArrayList.Itr",
    "java.util.ArrayList.ListItr",
    "java.util.ArrayList.SubList",
    "java.util.LinkedHashMap.LinkedKeySet",
    "java.util.LinkedHashMap.LinkedValues",
    "java.util.LinkedHashMap.LinkedEntrySet",
    "java.util.LinkedHashMap.LinkedKeyIterator",
    "java.util.LinkedHashMap.LinkedValueIterator",
    "java.util.LinkedHashMap.LinkedEntryIterator",
    "java.util.LinkedHashMap.Entry",
    "java.util.HashMap.KeySet",
    "java.util.HashMap.Values",
    "java.util.HashMap.EntrySet",
    "java.util.HashMap.KeyIterator",
    "java.util.HashMap.ValueIterator",
    "java.util.HashMap.EntryIterator",
    "java.util.HashMap.Node",
    "java.util.TreeMap.KeySet",
    "java.util.TreeMap.Values",
    "java.util.TreeMap.EntrySet",
    "java.util.TreeMap.KeyIterator",
    "java.util.TreeMap.ValueIterator",
    "java.util.TreeMap.EntryIterator",
    "java.util.TreeMap.Entry",
    "java.util.TreeMap.DescendingKeyIterator",
    "kotlin.collections.builders.ListBuilder.Itr",
    "kotlin.collections.builders.MapBuilder.KeysItr",
    "kotlin.collections.builders.MapBuilder.ValuesItr",
    "kotlin.collections.builders.MapBuilder.EntriesItr",
    "kotlin.collections.builders.MapBuilder.Keys",
    "kotlin.collections.builders.MapBuilder.Values",
    "kotlin.collections.builders.MapBuilder.Entries",
    "kotlin.collections.builders.MapBuilder.EntrySet",
    "kotlin.collections.builders.MapBuilder.KeySet",
    "kotlin.collections.AbstractList.IteratorImpl",
    "kotlin.collections.AbstractList.ListIteratorImpl",
]

private let runtimeJavaDeeplyNestedImplClassNames: Set<String> = [
    "java.util.TreeMap.NavigableSubMap.DescendingSubMapKeyIterator",
]

enum RuntimeReflectedClassIdentity {
    case named(typeID: Int64, qualifiedName: String)
    case anonymous(typeID: Int64)
}

private let runtimeAnonymousSingletonIteratorClassID = runtimeStableNominalTypeID(
    fqName: "java.util.Collections.SingletonIterator"
)
private let runtimeAnonymousListViewIteratorClassID = runtimeStableNominalTypeID(
    fqName: "java.util.AbstractList.ListViewIterator"
)
private let runtimeAnonymousPrimitiveAsListClassID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.AnonymousPrimitiveArrayAsList"
)
private let runtimeAnonymousSequenceIteratorClassID = runtimeStableNominalTypeID(
    fqName: "kotlin.sequences.AnonymousSequenceIterator"
)
private let runtimeAnonymousMiscIteratorClassID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.AnonymousMiscIterator"
)

private func runtimeReflectedImplTypeID(_ qualifiedName: String) -> Int64 {
    runtimeStableNominalTypeID(fqName: qualifiedName)
}

private func runtimeRegisterAnonymousReflectedClass(_ typeID: Int64) {
    let token = Int(truncatingIfNeeded:
        (typeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift
            | RuntimeTypeTokenEncoding.nominalBase)
    runtimeKClassMetadataRegistry.register(
        typeToken: token,
        entry: RuntimeKClassMetadataEntry(
            qualifiedName: "",
            simpleName: "",
            supertypeDisplayNames: [],
            isDataClass: false,
            isSealedClass: false,
            isValueClass: false,
            isInterface: false,
            isObject: false,
            isEnumClass: false,
            isAbstract: false,
            fieldCount: -1,
            memberCount: -1,
            constructorCount: -1,
            isFinal: true,
            isOpen: false,
            visibility: "PUBLIC",
            isLocal: true,
            isAnonymous: true
        )
    )
}

func runtimeEnsureReflectedClassMetadata(_ identity: RuntimeReflectedClassIdentity) {
    if case .anonymous(let typeID) = identity {
        runtimeRegisterAnonymousReflectedClass(typeID)
    }
}

private enum RuntimeMapViewKind {
    case keys
    case values
    case entries
}

private func runtimeObjectRawValue(_ box: AnyObject) -> Int {
    Int(bitPattern: Unmanaged.passUnretained(box).toOpaque())
}

func runtimeReflectedCollectionClass(rawValue: Int, typeID: Int64) -> RuntimeReflectedClassIdentity? {
    if let identity = runtimeReflectedIteratorClass(rawValue: rawValue) {
        return identity
    }
    if typeID == mapEntryRuntimeTypeID || typeID == mutableMapEntryRuntimeTypeID {
        return runtimeReflectedMapEntryClass(rawValue: rawValue)
    }
    if let flags = runtimeListViewTypeIDFlags(typeID),
       let list = runtimeListBox(from: rawValue)
    {
        return runtimeReflectedListViewClass(
            list: list,
            mutable: flags.mutable,
            randomAccess: flags.randomAccess
        )
    }
    switch typeID {
    case singletonListRuntimeTypeID:
        return .named(typeID: typeID, qualifiedName: "java.util.Collections.SingletonList")
    case arraysBackedListRuntimeTypeID:
        return .named(typeID: typeID, qualifiedName: "java.util.Arrays.ArrayList")
    case runtimeListBuilderTypeID:
        return .named(
            typeID: typeID,
            qualifiedName: "kotlin.collections.builders.ListBuilder"
        )
    case listRuntimeTypeID, mutableListRuntimeTypeID:
        guard let list = runtimeListBox(from: rawValue) else { return nil }
        if let identity = runtimeReflectedListViewClass(
            list: list,
            mutable: false,
            randomAccess: false
        ) {
            return identity
        }
        if list.count == 0, rawValue == emptyListSingletonRaw {
            return .named(
                typeID: runtimeReflectedImplTypeID("kotlin.collections.EmptyList"),
                qualifiedName: "kotlin.collections.EmptyList"
            )
        }
        return .named(
            typeID: arrayListRuntimeTypeID,
            qualifiedName: "kotlin.collections.ArrayList"
        )
    case mutableMapViewCollectionRuntimeTypeID:
        guard let list = runtimeListBox(from: rawValue),
              let mapRaw = list.mapValuesViewBackingRaw
        else { return nil }
        return runtimeReflectedMapValuesViewClass(mapRaw: mapRaw)
    case setRuntimeTypeID, mutableMapViewSetRuntimeTypeID:
        guard let set = runtimeSetBox(from: rawValue) else { return nil }
        return runtimeReflectedSetClass(rawValue: rawValue, set: set)
    case runtimeSetBuilderTypeID:
        return .named(
            typeID: typeID,
            qualifiedName: "kotlin.collections.builders.SetBuilder"
        )
    case sortedSetRuntimeTypeID, navigableSetRuntimeTypeID:
        guard let set = runtimeSetBox(from: rawValue) else { return nil }
        if let (mapRaw, kind) = set.mapViewBacking {
            return runtimeReflectedMapSetViewClass(mapRaw: mapRaw, kind: kind)
        }
        return .named(typeID: treeSetRuntimeTypeID, qualifiedName: "java.util.TreeSet")
    case mapRuntimeTypeID:
        guard let map = runtimeMapBox(from: rawValue) else { return nil }
        if map.usesReferenceEquality {
            return .named(
                typeID: runtimeReflectedImplTypeID("java.util.IdentityHashMap"),
                qualifiedName: "java.util.IdentityHashMap"
            )
        }
        switch map.count {
        case 0 where rawValue == emptyMapSingletonRaw:
            return .named(
                typeID: runtimeReflectedImplTypeID("kotlin.collections.EmptyMap"),
                qualifiedName: "kotlin.collections.EmptyMap"
            )
        case 1 where map.isEffectivelyReadOnly:
            // KUU-3962: same singleton-vs-LinkedHashMap split as sets — a
            // one-entry map deduplicated from `mapOf(k to v1, k to v2)` is a
            // mutable `LinkedHashMap` on the JVM.
            return .named(
                typeID: runtimeReflectedImplTypeID("java.util.Collections.SingletonMap"),
                qualifiedName: "java.util.Collections.SingletonMap"
            )
        default:
            return .named(
                typeID: linkedHashMapRuntimeTypeID,
                qualifiedName: "kotlin.collections.LinkedHashMap"
            )
        }
    case mutableMapRuntimeTypeID:
        return .named(
            typeID: runtimeReflectedImplTypeID("kotlin.collections.builders.MapBuilder"),
            qualifiedName: "kotlin.collections.builders.MapBuilder"
        )
    default:
        return nil
    }
}

private func runtimeReflectedListViewClass(
    list: RuntimeListBox,
    mutable: Bool,
    randomAccess: Bool
) -> RuntimeReflectedClassIdentity? {
    if list.isSubListStorageView {
        if let base = list.subListBaseBox,
           runtimeObjectTypeID(rawValue: runtimeObjectRawValue(base)) == arrayListRuntimeTypeID
        {
            return .named(
                typeID: runtimeReflectedImplTypeID("java.util.ArrayList.SubList"),
                qualifiedName: "java.util.ArrayList.SubList"
            )
        }
        let name = randomAccess
            ? "java.util.AbstractList.RandomAccessSubList"
            : "java.util.AbstractList.SubList"
        return .named(typeID: runtimeReflectedImplTypeID(name), qualifiedName: name)
    }
    if list.isReversedStorageView {
        let name = mutable
            ? "kotlin.collections.ReversedList"
            : "kotlin.collections.ReversedListReadOnly"
        return .named(typeID: runtimeReflectedImplTypeID(name), qualifiedName: name)
    }
    if let mapRaw = list.mapValuesViewBackingRaw {
        return runtimeReflectedMapValuesViewClass(mapRaw: mapRaw)
    }
    if list.isArrayStorageView {
        if list.isPrimitiveArrayView {
            return .anonymous(typeID: runtimeAnonymousPrimitiveAsListClassID)
        }
        return .named(
            typeID: arraysBackedListRuntimeTypeID,
            qualifiedName: "java.util.Arrays.ArrayList"
        )
    }
    return nil
}

private func runtimeReflectedSetClass(rawValue: Int, set: RuntimeSetBox) -> RuntimeReflectedClassIdentity {
    if let (mapRaw, kind) = set.mapViewBacking {
        return runtimeReflectedMapSetViewClass(mapRaw: mapRaw, kind: kind)
    }
    if set.sorted {
        return .named(typeID: treeSetRuntimeTypeID, qualifiedName: "java.util.TreeSet")
    }
    switch set.count {
    case 0 where rawValue == emptySetSingletonRaw:
        return .named(
            typeID: runtimeReflectedImplTypeID("kotlin.collections.EmptySet"),
            qualifiedName: "kotlin.collections.EmptySet"
        )
    case 1 where set.isEffectivelyReadOnly:
        // KUU-3962: only the unmodifiable singleton reads as
        // `Collections$SingletonSet`; a one-element set produced by
        // `setOf(e1, e1)` dedup is a `LinkedHashSet` like the JVM.
        return .named(
            typeID: runtimeReflectedImplTypeID("java.util.Collections.SingletonSet"),
            qualifiedName: "java.util.Collections.SingletonSet"
        )
    default:
        return .named(
            typeID: linkedHashSetRuntimeTypeID,
            qualifiedName: "kotlin.collections.LinkedHashSet"
        )
    }
}

private func runtimeReflectedMapSetViewClass(
    mapRaw: Int,
    kind: RuntimeSetBox.MapViewKind
) -> RuntimeReflectedClassIdentity {
    let mapTag = runtimeObjectTypeID(rawValue: mapRaw)
    let map = runtimeMapBox(from: mapRaw)
    switch map?.count ?? 0 {
    case 0 where mapRaw == emptyMapSingletonRaw:
        return .named(
            typeID: runtimeReflectedImplTypeID("kotlin.collections.EmptySet"),
            qualifiedName: "kotlin.collections.EmptySet"
        )
    case 1 where mapTag == mapRuntimeTypeID && map?.isEffectivelyReadOnly == true:
        return .named(
            typeID: runtimeReflectedImplTypeID("java.util.Collections.SingletonSet"),
            qualifiedName: "java.util.Collections.SingletonSet"
        )
    default:
        break
    }
    let keys = kind == .keys
    let name: String = switch mapTag {
    case hashMapRuntimeTypeID:
        keys ? "java.util.HashMap.KeySet" : "java.util.HashMap.EntrySet"
    case treeMapRuntimeTypeID, sortedMapRuntimeTypeID, navigableMapRuntimeTypeID:
        keys ? "java.util.TreeMap.KeySet" : "java.util.TreeMap.EntrySet"
    case mutableMapRuntimeTypeID:
        keys
            ? "kotlin.collections.builders.MapBuilder.KeySet"
            : "kotlin.collections.builders.MapBuilder.EntrySet"
    default:
        keys
            ? "java.util.LinkedHashMap.LinkedKeySet"
            : "java.util.LinkedHashMap.LinkedEntrySet"
    }
    return .named(typeID: runtimeReflectedImplTypeID(name), qualifiedName: name)
}

private func runtimeReflectedMapValuesViewClass(mapRaw: Int) -> RuntimeReflectedClassIdentity {
    let mapTag = runtimeObjectTypeID(rawValue: mapRaw)
    let map = runtimeMapBox(from: mapRaw)
    switch map?.count ?? 0 {
    case 0 where mapRaw == emptyMapSingletonRaw:
        return .named(
            typeID: runtimeReflectedImplTypeID("kotlin.collections.EmptyList"),
            qualifiedName: "kotlin.collections.EmptyList"
        )
    case 1 where mapTag == mapRuntimeTypeID && map?.isEffectivelyReadOnly == true:
        return .named(
            typeID: runtimeReflectedImplTypeID("java.util.Collections.SingletonSet"),
            qualifiedName: "java.util.Collections.SingletonSet"
        )
    default:
        break
    }
    let name: String = switch mapTag {
    case hashMapRuntimeTypeID:
        "java.util.HashMap.Values"
    case treeMapRuntimeTypeID, sortedMapRuntimeTypeID, navigableMapRuntimeTypeID:
        "java.util.TreeMap.Values"
    case mutableMapRuntimeTypeID:
        "kotlin.collections.builders.MapBuilder.Values"
    default:
        "java.util.LinkedHashMap.LinkedValues"
    }
    return .named(typeID: runtimeReflectedImplTypeID(name), qualifiedName: name)
}

private func runtimeReflectedMapEntryClass(rawValue: Int) -> RuntimeReflectedClassIdentity {
    guard let pair = resolveRuntimeHandle(rawValue, as: RuntimePairBox.self),
          pair.mutableMapRaw != 0
    else {
        return .named(
            typeID: runtimeReflectedImplTypeID("java.util.AbstractMap.SimpleImmutableEntry"),
            qualifiedName: "java.util.AbstractMap.SimpleImmutableEntry"
        )
    }
    let name: String = switch runtimeObjectTypeID(rawValue: pair.mutableMapRaw) {
    case hashMapRuntimeTypeID:
        "java.util.HashMap.Node"
    case treeMapRuntimeTypeID, sortedMapRuntimeTypeID, navigableMapRuntimeTypeID:
        "java.util.TreeMap.Entry"
    case mapRuntimeTypeID:
        if let map = runtimeMapBox(from: pair.mutableMapRaw),
           map.count <= 1, map.isEffectivelyReadOnly
        {
            "java.util.AbstractMap.SimpleImmutableEntry"
        } else {
            "java.util.LinkedHashMap.Entry"
        }
    default:
        "java.util.LinkedHashMap.Entry"
    }
    return .named(typeID: runtimeReflectedImplTypeID(name), qualifiedName: name)
}

private func runtimeReflectedIteratorClass(rawValue: Int) -> RuntimeReflectedClassIdentity? {
    if let iterator = runtimeListIteratorBox(from: rawValue) {
        guard iterator.reflectedClassID != 0 else { return nil }
        if let name = iterator.reflectedClassName {
            return .named(typeID: iterator.reflectedClassID, qualifiedName: name)
        }
        return .anonymous(typeID: iterator.reflectedClassID)
    }
    if let iterator = runtimeMapIteratorBox(from: rawValue) {
        return runtimeReflectedMapViewIteratorClass(mapRaw: iterator.mapRaw, kind: .entries)
    }
    if let iterator = runtimeMutableMapIteratorBox(from: rawValue) {
        return runtimeReflectedMapViewIteratorClass(mapRaw: iterator.mapRaw, kind: .entries)
    }
    if resolveRuntimeHandle(rawValue, as: RuntimeSequenceIteratorBox.self) != nil {
        return .anonymous(typeID: runtimeAnonymousSequenceIteratorClassID)
    }
    if resolveRuntimeHandle(rawValue, as: RuntimeIndexingIteratorBox.self) != nil
        || resolveRuntimeHandle(rawValue, as: RuntimeIteratorBuilderBox.self) != nil
        || resolveRuntimeHandle(rawValue, as: RuntimeBufferedLineIteratorBox.self) != nil
    {
        return .anonymous(typeID: runtimeAnonymousMiscIteratorClassID)
    }
    return nil
}

private func runtimeReflectedMapViewIteratorClass(
    mapRaw: Int,
    kind: RuntimeMapViewKind
) -> RuntimeReflectedClassIdentity {
    let (typeID, name) = runtimeReflectedMapViewIteratorName(mapRaw: mapRaw, kind: kind)
    if let name {
        return .named(typeID: typeID, qualifiedName: name)
    }
    return .anonymous(typeID: typeID)
}

private func runtimeReflectedMapViewIteratorName(
    mapRaw: Int,
    kind: RuntimeMapViewKind
) -> (typeID: Int64, qualifiedName: String?) {
    let mapTag = runtimeObjectTypeID(rawValue: mapRaw)
    let map = runtimeMapBox(from: mapRaw)
    switch map?.count ?? 0 {
    case 0 where mapRaw == emptyMapSingletonRaw:
        let name = "kotlin.collections.EmptyIterator"
        return (runtimeReflectedImplTypeID(name), name)
    case 1 where mapTag == mapRuntimeTypeID && map?.isEffectivelyReadOnly == true:
        return (runtimeAnonymousSingletonIteratorClassID, nil)
    default:
        break
    }
    let name: String = switch (mapTag, kind) {
    case (hashMapRuntimeTypeID, .keys):
        "java.util.HashMap.KeyIterator"
    case (hashMapRuntimeTypeID, .values):
        "java.util.HashMap.ValueIterator"
    case (hashMapRuntimeTypeID, .entries):
        "java.util.HashMap.EntryIterator"
    case (treeMapRuntimeTypeID, .keys),
         (sortedMapRuntimeTypeID, .keys),
         (navigableMapRuntimeTypeID, .keys):
        "java.util.TreeMap.KeyIterator"
    case (treeMapRuntimeTypeID, .values),
         (sortedMapRuntimeTypeID, .values),
         (navigableMapRuntimeTypeID, .values):
        "java.util.TreeMap.ValueIterator"
    case (treeMapRuntimeTypeID, .entries),
         (sortedMapRuntimeTypeID, .entries),
         (navigableMapRuntimeTypeID, .entries):
        "java.util.TreeMap.EntryIterator"
    case (mutableMapRuntimeTypeID, .keys):
        "kotlin.collections.builders.MapBuilder.KeysItr"
    case (mutableMapRuntimeTypeID, .values):
        "kotlin.collections.builders.MapBuilder.ValuesItr"
    case (mutableMapRuntimeTypeID, .entries):
        "kotlin.collections.builders.MapBuilder.EntriesItr"
    case (_, .keys):
        "java.util.LinkedHashMap.LinkedKeyIterator"
    case (_, .values):
        "java.util.LinkedHashMap.LinkedValueIterator"
    case (_, .entries):
        "java.util.LinkedHashMap.LinkedEntryIterator"
    }
    return (runtimeReflectedImplTypeID(name), name)
}

func runtimeReflectedListIteratorClass(
    sourceRaw: Int,
    list: RuntimeListBox,
    listIterator: Bool
) -> (typeID: Int64, qualifiedName: String?) {
    if let mapRaw = list.mapValuesViewBackingRaw {
        return runtimeReflectedMapViewIteratorName(mapRaw: mapRaw, kind: .values)
    }
    if list.isSubListStorageView || list.isReversedStorageView {
        return (runtimeAnonymousListViewIteratorClassID, nil)
    }
    if list.isArrayStorageView {
        if list.isPrimitiveArrayView {
            let name = listIterator
                ? "kotlin.collections.AbstractList.ListIteratorImpl"
                : "kotlin.collections.AbstractList.IteratorImpl"
            return (runtimeReflectedImplTypeID(name), name)
        }
        let name = listIterator
            ? "java.util.AbstractList.ListItr"
            : "java.util.Arrays.ArrayItr"
        return (runtimeReflectedImplTypeID(name), name)
    }
    switch runtimeObjectTypeID(rawValue: sourceRaw) {
    case singletonListRuntimeTypeID:
        return listIterator
            ? (runtimeReflectedImplTypeID("java.util.AbstractList.ListItr"), "java.util.AbstractList.ListItr")
            : (runtimeAnonymousSingletonIteratorClassID, nil)
    case arraysBackedListRuntimeTypeID:
        return listIterator
            ? (runtimeReflectedImplTypeID("java.util.AbstractList.ListItr"), "java.util.AbstractList.ListItr")
            : (runtimeReflectedImplTypeID("java.util.Arrays.ArrayItr"), "java.util.Arrays.ArrayItr")
    case arrayDequeRuntimeTypeID:
        let name = listIterator ? "java.util.AbstractList.ListItr" : "java.util.AbstractList.Itr"
        return (runtimeReflectedImplTypeID(name), name)
    case runtimeListBuilderTypeID:
        return (
            runtimeReflectedImplTypeID("kotlin.collections.builders.ListBuilder.Itr"),
            "kotlin.collections.builders.ListBuilder.Itr"
        )
    case arrayListRuntimeTypeID, listRuntimeTypeID, mutableListRuntimeTypeID:
        if list.count == 0, sourceRaw == emptyListSingletonRaw {
            let name = "kotlin.collections.EmptyIterator"
            return (runtimeReflectedImplTypeID(name), name)
        }
        let name = listIterator ? "java.util.ArrayList.ListItr" : "java.util.ArrayList.Itr"
        return (runtimeReflectedImplTypeID(name), name)
    default:
        return (0, nil)
    }
}

func runtimeReflectedSetIteratorClass(
    setRaw: Int,
    set: RuntimeSetBox
) -> (typeID: Int64, qualifiedName: String?) {
    if let (mapRaw, kind) = set.mapViewBacking {
        return runtimeReflectedMapViewIteratorName(
            mapRaw: mapRaw,
            kind: kind == .keys ? .keys : .entries
        )
    }
    let setTag = runtimeObjectTypeID(rawValue: setRaw)
    if set.sorted
        || setTag == treeSetRuntimeTypeID
        || setTag == sortedSetRuntimeTypeID
        || setTag == navigableSetRuntimeTypeID
    {
        let name = "java.util.TreeMap.KeyIterator"
        return (runtimeReflectedImplTypeID(name), name)
    }
    switch setTag {
    case hashSetRuntimeTypeID:
        let name = "java.util.HashMap.KeyIterator"
        return (runtimeReflectedImplTypeID(name), name)
    case linkedHashSetRuntimeTypeID:
        let name = "java.util.LinkedHashMap.LinkedKeyIterator"
        return (runtimeReflectedImplTypeID(name), name)
    case runtimeSetBuilderTypeID:
        let name = "kotlin.collections.builders.MapBuilder.KeysItr"
        return (runtimeReflectedImplTypeID(name), name)
    default:
        switch set.count {
        case 0 where setRaw == emptySetSingletonRaw:
            let name = "kotlin.collections.EmptyIterator"
            return (runtimeReflectedImplTypeID(name), name)
        case 1 where set.isEffectivelyReadOnly:
            // KUU-3962: the anonymous singleton iterator only applies to the
            // unmodifiable singleton; dedup-to-one sets keep the
            // `LinkedHashMap` node iterator.
            return (runtimeAnonymousSingletonIteratorClassID, nil)
        default:
            let name = "java.util.LinkedHashMap.LinkedKeyIterator"
            return (runtimeReflectedImplTypeID(name), name)
        }
    }
}
