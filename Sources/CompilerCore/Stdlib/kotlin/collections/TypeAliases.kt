package kotlin.collections

// KSP-627
// JVM-flavoured collection aliases. On KSwiftK the mutable collection
// interfaces are the concrete representation, so the JDK class names are plain
// type aliases; CollectionLiteralLoweringPass rewrites `ArrayList()`-style
// constructor calls to the matching runtime bridge.

public typealias ArrayList<E> = MutableList<E>

public typealias HashSet<E> = MutableSet<E>

public typealias HashMap<K, V> = MutableMap<K, V>

public typealias LinkedHashMap<K, V> = MutableMap<K, V>

public open class LinkedHashSet<E> : MutableSet<E> {
    constructor()
    constructor(initialCapacity: Int)
    constructor(elements: Collection<E>)
}
