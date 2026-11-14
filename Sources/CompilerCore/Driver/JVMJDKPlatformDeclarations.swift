import Foundation

extension JVMClasspathIndex {
    /// A small source profile preserves Kotlin generics at JDK boundaries.
    /// Bodies remain in the JDK; no java.* classes are emitted into our stdlib.
    func injectJDKPlatformDeclarations(into ctx: CompilationContext) throws {
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let comparator: JVMValueType = .reference("java/util/Comparator", nullable: false)
        let extractor: JVMValueType = .reference("java/util/function/ToIntFunction", nullable: false)
        func method(_ owner: String, _ name: String, _ parameters: [JVMValueType], _ result: JVMValueType, staticMember: Bool = false, interface: Bool = false, varargs: Bool = false) -> JVMForeignMethod {
            var foreign = JVMForeignMethod(owner: owner, name: name, descriptor: "(" + parameters.map(\.descriptor).joined() + ")" + (name == "<init>" ? "V" : result.descriptor), parameters: parameters, result: result, isStatic: staticMember, isInterface: interface, isAbstract: interface && !staticMember)
            foreign.isVarargs = varargs
            return foreign
        }
        let objectArray = JVMValueType.reference("[Ljava/lang/Object;", nullable: false)
        let nullableObjectArray = JVMValueType.reference("[Ljava/lang/Object;", nullable: true)
        var arraysMethods = [
            method("java/util/Arrays", "copyOf", [objectArray, .int], objectArray, staticMember: true),
            method("java/util/Arrays", "copyOfRange", [objectArray, .int, .int], objectArray, staticMember: true),
            method("java/util/Arrays", "fill", [objectArray, .int, .int, object], .unit, staticMember: true),
            method("java/util/Arrays", "equals", [nullableObjectArray, nullableObjectArray], .boolean, staticMember: true),
            method("java/util/Arrays", "hashCode", [nullableObjectArray], .int, staticMember: true),
            method("java/util/Arrays", "toString", [nullableObjectArray], .string, staticMember: true),
            method("java/util/Arrays", "deepEquals", [nullableObjectArray, nullableObjectArray], .boolean, staticMember: true),
            method("java/util/Arrays", "deepHashCode", [nullableObjectArray], .int, staticMember: true),
            method("java/util/Arrays", "deepToString", [nullableObjectArray], .string, staticMember: true),
            method("java/util/Arrays", "sort", [objectArray], .unit, staticMember: true),
            method("java/util/Arrays", "sort", [objectArray, .int, .int], .unit, staticMember: true),
            method("java/util/Arrays", "sort", [objectArray, .reference("java/util/Comparator", nullable: true)], .unit, staticMember: true),
            method("java/util/Arrays", "sort", [objectArray, .int, .int, .reference("java/util/Comparator", nullable: true)], .unit, staticMember: true),
            method("java/util/Arrays", "binarySearch", [objectArray, .int, .int, .reference("java/lang/Object", nullable: true)], .int, staticMember: true),
        ]
        var arraysSource = """
            package java.util
            class Arrays private constructor() {
                companion object {
                    external fun <T> copyOf(a: Array<out T>, newLength: Int): Array<T>
                    external fun <T> copyOfRange(a: Array<out T>, fromIndex: Int, toIndex: Int): Array<T>
                    external fun fill(a: Array<out Any?>, fromIndex: Int, toIndex: Int, value: Any?): Unit
                    external fun equals(a: Array<out Any?>?, b: Array<out Any?>?): Boolean
                    external fun hashCode(a: Array<out Any?>?): Int
                    external fun toString(a: Array<out Any?>?): String
                    external fun deepEquals(a: Array<out Any?>?, b: Array<out Any?>?): Boolean
                    external fun deepHashCode(a: Array<out Any?>?): Int
                    external fun deepToString(a: Array<out Any?>?): String
                    external fun sort(a: Array<out Any?>): Unit
                    external fun sort(a: Array<out Any?>, fromIndex: Int, toIndex: Int): Unit
                    external fun <T> sort(a: Array<out T>, comparator: java.util.Comparator<in T>?): Unit
                    external fun <T> sort(a: Array<out T>, fromIndex: Int, toIndex: Int, comparator: java.util.Comparator<in T>?): Unit
                    external fun binarySearch(a: Array<out Any?>, fromIndex: Int, toIndex: Int, key: Any?): Int
            """
        let primitiveArraySpecs: [(name: String, type: String, descriptor: String, element: JVMValueType, canSort: Bool, canSearch: Bool)] = [
            ("Byte", "ByteArray", "[B", .byte, true, true),
            ("Short", "ShortArray", "[S", .short, true, true),
            ("Int", "IntArray", "[I", .int, true, true),
            ("Long", "LongArray", "[J", .long, true, true),
            ("Float", "FloatArray", "[F", .float, true, true),
            ("Double", "DoubleArray", "[D", .double, true, true),
            ("Char", "CharArray", "[C", .char, true, true),
            ("Boolean", "BooleanArray", "[Z", .boolean, false, false),
        ]
        for spec in primitiveArraySpecs {
            let array = JVMValueType.reference(spec.descriptor, nullable: false)
            let nullableArray = JVMValueType.reference(spec.descriptor, nullable: true)
            arraysSource += "\n                    external fun equals(a: \(spec.type)?, b: \(spec.type)?): Boolean"
            arraysSource += "\n                    external fun hashCode(a: \(spec.type)?): Int"
            arraysSource += "\n                    external fun toString(a: \(spec.type)?): String"
            arraysSource += "\n                    external fun copyOf(a: \(spec.type), newLength: Int): \(spec.type)"
            arraysSource += "\n                    external fun copyOfRange(a: \(spec.type), fromIndex: Int, toIndex: Int): \(spec.type)"
            arraysSource += "\n                    external fun fill(a: \(spec.type), fromIndex: Int, toIndex: Int, value: \(spec.name)): Unit"
            arraysMethods.append(method("java/util/Arrays", "equals", [nullableArray, nullableArray], .boolean, staticMember: true))
            arraysMethods.append(method("java/util/Arrays", "hashCode", [nullableArray], .int, staticMember: true))
            arraysMethods.append(method("java/util/Arrays", "toString", [nullableArray], .string, staticMember: true))
            arraysMethods.append(method("java/util/Arrays", "copyOf", [array, .int], array, staticMember: true))
            arraysMethods.append(method("java/util/Arrays", "copyOfRange", [array, .int, .int], array, staticMember: true))
            arraysMethods.append(method("java/util/Arrays", "fill", [array, .int, .int, spec.element], .unit, staticMember: true))
            if spec.canSort {
                arraysSource += "\n                    external fun sort(a: \(spec.type)): Unit"
                arraysSource += "\n                    external fun sort(a: \(spec.type), fromIndex: Int, toIndex: Int): Unit"
                arraysMethods.append(method("java/util/Arrays", "sort", [array], .unit, staticMember: true))
                arraysMethods.append(method("java/util/Arrays", "sort", [array, .int, .int], .unit, staticMember: true))
            }
            if spec.canSearch {
                arraysSource += "\n                    external fun binarySearch(a: \(spec.type), fromIndex: Int, toIndex: Int, key: \(spec.name)): Int"
                arraysMethods.append(method("java/util/Arrays", "binarySearch", [array, .int, .int, spec.element], .int, staticMember: true))
            }
        }
        arraysSource += "\n                }\n            }\n"
        let declarations: [(String, String, UInt16, String?, [JVMForeignMethod])] = [
            ("java/lang/String", """
            package java.lang
            class String(value: kotlin.String) {
                companion object {
                    val CASE_INSENSITIVE_ORDER: kotlin.Comparator<kotlin.String> get() = null!!
                    external fun valueOf(value: Boolean): String
                    external fun valueOf(value: Char): String
                    external fun valueOf(value: CharArray): String
                    external fun valueOf(data: CharArray, offset: Int, count: Int): String
                    external fun valueOf(value: Double): String
                    external fun valueOf(value: Float): String
                    external fun valueOf(value: Int): String
                    external fun valueOf(value: Long): String
                    external fun valueOf(value: Any?): String
                    external fun join(delimiter: kotlin.CharSequence, vararg elements: kotlin.CharSequence): String
                    external fun join(delimiter: kotlin.CharSequence, elements: kotlin.collections.Iterable<out kotlin.CharSequence>): String
                    external fun copyValueOf(data: CharArray): String
                    external fun copyValueOf(data: CharArray, offset: Int, count: Int): String
                    external fun format(format: kotlin.String, vararg args: Any?): String
                    external fun format(locale: java.util.Locale, format: kotlin.String, vararg args: Any?): String
                }
                external fun getChars(srcBegin: Int, srcEnd: Int, dst: CharArray, dstBegin: Int)
                external fun contentEquals(other: kotlin.CharSequence): Boolean
                external fun regionMatches(thisOffset: Int, other: kotlin.String, otherOffset: Int, length: Int): Boolean
                external fun regionMatches(ignoreCase: Boolean, thisOffset: Int, other: kotlin.String, otherOffset: Int, length: Int): Boolean
            }
            """, 0x0011, "java/lang/Object", [
                method("java/lang/String", "<init>", [.string], .reference("java/lang/String", nullable: false)),
                method("java/lang/String", "valueOf", [.boolean], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/String", "valueOf", [.char], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/String", "valueOf", [.reference("[C", nullable: false)], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/String", "valueOf", [.reference("[C", nullable: false), .int, .int], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/String", "valueOf", [.double], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/String", "valueOf", [.float], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/String", "valueOf", [.int], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/String", "valueOf", [.long], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/String", "valueOf", [object], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/String", "join", [.reference("java/lang/CharSequence", nullable: false), .reference("[Ljava/lang/CharSequence;", nullable: false)], .reference("java/lang/String", nullable: false), staticMember: true, varargs: true),
                method("java/lang/String", "join", [.reference("java/lang/CharSequence", nullable: false), .reference("java/lang/Iterable", nullable: false)], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/String", "copyValueOf", [.reference("[C", nullable: false)], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/String", "copyValueOf", [.reference("[C", nullable: false), .int, .int], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/String", "format", [.string, .reference("[Ljava/lang/Object;", nullable: false)], .reference("java/lang/String", nullable: false), staticMember: true, varargs: true),
                method("java/lang/String", "format", [.reference("java/util/Locale", nullable: false), .string, .reference("[Ljava/lang/Object;", nullable: false)], .reference("java/lang/String", nullable: false), staticMember: true, varargs: true),
                method("java/lang/String", "getChars", [.int, .int, .reference("[C", nullable: false), .int], .unit),
                method("java/lang/String", "contentEquals", [.reference("java/lang/CharSequence", nullable: false)], .boolean),
                method("java/lang/String", "regionMatches", [.int, .string, .int, .int], .boolean),
                method("java/lang/String", "regionMatches", [.boolean, .int, .string, .int, .int], .boolean),
            ]),
            ("java/lang/Math", """
            package java.lang
            class Math private constructor() {
                companion object {
                    const val PI: Double = 3.141592653589793
                    const val E: Double = 2.718281828459045
                    external fun min(a: Int, b: Int): Int
                    external fun max(a: Int, b: Int): Int
                    external fun min(a: Long, b: Long): Long
                    external fun max(a: Long, b: Long): Long
                    external fun min(a: Double, b: Double): Double
                    external fun max(a: Double, b: Double): Double
                    external fun min(a: Float, b: Float): Float
                    external fun max(a: Float, b: Float): Float
                }
            }
            """, 0x0011, "java/lang/Object", [
                method("java/lang/Math", "min", [.int, .int], .int, staticMember: true),
                method("java/lang/Math", "max", [.int, .int], .int, staticMember: true),
                method("java/lang/Math", "min", [.long, .long], .long, staticMember: true),
                method("java/lang/Math", "max", [.long, .long], .long, staticMember: true),
                method("java/lang/Math", "min", [.double, .double], .double, staticMember: true),
                method("java/lang/Math", "max", [.double, .double], .double, staticMember: true),
                method("java/lang/Math", "min", [.float, .float], .float, staticMember: true),
                method("java/lang/Math", "max", [.float, .float], .float, staticMember: true),
            ]),
            ("java/lang/System", """
            package java.lang
            class System private constructor() {
                companion object {
                    external fun getProperty(propertyName: kotlin.String): kotlin.String?
                    external fun getProperty(propertyName: kotlin.String, defaultValue: kotlin.String): kotlin.String
                    external fun currentTimeMillis(): Long
                    external fun nanoTime(): Long
                    external fun arraycopy(src: Any?, srcPos: Int, dest: Any?, destPos: Int, length: Int): Unit
                }
            }
            """, 0x0011, "java/lang/Object", [
                method("java/lang/System", "getProperty", [.string], .reference("java/lang/String", nullable: true), staticMember: true),
                method("java/lang/System", "getProperty", [.string, .string], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/System", "currentTimeMillis", [], .long, staticMember: true),
                method("java/lang/System", "nanoTime", [], .long, staticMember: true),
                method("java/lang/System", "arraycopy", [object, .int, object, .int, .int], .unit, staticMember: true),
            ]),
            ("java/lang/StackTraceElement", """
            package java.lang
            class StackTraceElement private constructor()
            """, 0x0011, "java/lang/Object", []),
            ("java/lang/IllegalAccessError", """
            package java.lang
            open class IllegalAccessError : kotlin.Error {
                constructor() : super()
            }
            """, 0x0001, "java/lang/IncompatibleClassChangeError", [
                method("java/lang/IllegalAccessError", "<init>", [], .reference("java/lang/IllegalAccessError", nullable: false)),
            ]),
            ("java/lang/Integer", """
            package java.lang
            class Integer private constructor() {
                companion object {
                    const val MAX_VALUE: Int = 2147483647
                    const val MIN_VALUE: Int = -2147483647 - 1
                    external fun parseInt(value: kotlin.String): Int
                    external fun parseInt(value: kotlin.String, radix: Int): Int
                }
            }
            """, 0x0011, "java/lang/Number", [
                method("java/lang/Integer", "parseInt", [.string], .int, staticMember: true),
                method("java/lang/Integer", "parseInt", [.string, .int], .int, staticMember: true),
            ]),
            ("java/lang/Character", """
            package java.lang
            class Character private constructor() {
                companion object {
                    external fun isDigit(value: Char): Boolean
                    external fun isDigit(value: Int): Boolean
                    external fun toUpperCase(value: Char): Char
                    external fun toUpperCase(value: Int): Int
                }
            }
            """, 0x0011, "java/lang/Object", [
                method("java/lang/Character", "isDigit", [.char], .boolean, staticMember: true),
                method("java/lang/Character", "isDigit", [.int], .boolean, staticMember: true),
                method("java/lang/Character", "toUpperCase", [.char], .char, staticMember: true),
                method("java/lang/Character", "toUpperCase", [.int], .int, staticMember: true),
            ]),
            ("java/util/Arrays", arraysSource, 0x0031, "java/lang/Object", arraysMethods),
            ("java/util/function/ToIntFunction", """
            package java.util.function
            fun interface ToIntFunction<T> { fun applyAsInt(value: T): Int }
            """, 0x0601, "java/lang/Object", [method("java/util/function/ToIntFunction", "applyAsInt", [object], .int, interface: true)]),
            ("java/lang/Runnable", """
            package java.lang
            fun interface Runnable {
                fun run()
            }
            """, 0x0601, "java/lang/Object", [
                method("java/lang/Runnable", "run", [], .unit, interface: true),
            ]),
            ("java/util/concurrent/Callable", """
            package java.util.concurrent
            fun interface Callable<V> {
                fun call(): V
            }
            """, 0x0601, "java/lang/Object", [
                method("java/util/concurrent/Callable", "call", [], object, interface: true),
            ]),
            ("java/util/Comparator", """
            package java.util
            fun interface Comparator<T> {
                fun compare(first: T, second: T): Int
                companion object {
                    external fun <T> comparingInt(keyExtractor: java.util.function.ToIntFunction<in T>): java.util.Comparator<T>
                }
            }
            """, 0x0601, "java/lang/Object", [method("java/util/Comparator", "compare", [object, object], .int, interface: true), method("java/util/Comparator", "comparingInt", [extractor], comparator, staticMember: true, interface: true)]),
            ("java/util/HashMap", """
            package java.util
            open class HashMap<K, V> : kotlin.collections.MutableMap<K, V> {
                constructor()
                override val size: Int get() = 0
                override val keys: kotlin.collections.Set<K> get() = null!!
                override val values: kotlin.collections.Collection<V> get() = null!!
                override val entries: kotlin.collections.MutableSet<kotlin.collections.MutableMap.MutableEntry<K, V>> get() = null!!
                override fun get(key: K): V? = null
                override fun containsKey(key: K): Boolean = false
                override fun containsValue(value: V): Boolean = false
                override fun isEmpty(): Boolean = false
                override fun put(key: K, value: V): V? = null
                override operator fun set(key: K, value: V) {}
                override fun remove(key: K): V? = null
                override fun clear() {}
            }
            """, 0x0001, "java/lang/Object", [
                method("java/util/HashMap", "<init>", [], .reference("java/util/HashMap", nullable: false)),
                method("java/util/HashMap", "put", [object, object], object),
            ]),
            ("java/util/LinkedHashMap", """
            package java.util
            open class LinkedHashMap<K, V> : kotlin.collections.MutableMap<K, V> {
                constructor()
                override val size: Int get() = 0
                override val keys: kotlin.collections.Set<K> get() = null!!
                override val values: kotlin.collections.Collection<V> get() = null!!
                override val entries: kotlin.collections.MutableSet<kotlin.collections.MutableMap.MutableEntry<K, V>> get() = null!!
                override fun get(key: K): V? = null
                override fun containsKey(key: K): Boolean = false
                override fun containsValue(value: V): Boolean = false
                override fun isEmpty(): Boolean = false
                override fun put(key: K, value: V): V? = null
                override operator fun set(key: K, value: V) {}
                override fun remove(key: K): V? = null
                override fun clear() {}
            }
            """, 0x0001, "java/util/HashMap", [
                method("java/util/LinkedHashMap", "<init>", [], .reference("java/util/LinkedHashMap", nullable: false)),
                method("java/util/LinkedHashMap", "put", [object, object], object),
            ]),
            ("java/util/SortedMap", """
            package java.util
            interface SortedMap<K, V> : kotlin.collections.MutableMap<K, V> {
                fun comparator(): kotlin.Comparator<in K>?
                fun firstKey(): K
                fun lastKey(): K
                fun headMap(toKey: K): SortedMap<K, V>
                fun tailMap(fromKey: K): SortedMap<K, V>
                fun subMap(fromKey: K, toKey: K): SortedMap<K, V>
            }
            """, 0x0601, "java/lang/Object", [
                method("java/util/SortedMap", "comparator", [], .reference("java/util/Comparator", nullable: true), interface: true),
                method("java/util/SortedMap", "firstKey", [], object, interface: true),
                method("java/util/SortedMap", "lastKey", [], object, interface: true),
                method("java/util/SortedMap", "headMap", [object], .reference("java/util/SortedMap", nullable: false), interface: true),
                method("java/util/SortedMap", "tailMap", [object], .reference("java/util/SortedMap", nullable: false), interface: true),
                method("java/util/SortedMap", "subMap", [object, object], .reference("java/util/SortedMap", nullable: false), interface: true),
            ]),
            ("java/util/SortedSet", """
            package java.util
            interface SortedSet<E> : kotlin.collections.MutableSet<E> {
                fun comparator(): kotlin.Comparator<in E>?
                fun first(): E
                fun last(): E
                fun headSet(toElement: E): SortedSet<E>
                fun tailSet(fromElement: E): SortedSet<E>
                fun subSet(fromElement: E, toElement: E): SortedSet<E>
            }
            """, 0x0601, "java/lang/Object", [
                method("java/util/SortedSet", "comparator", [], .reference("java/util/Comparator", nullable: true), interface: true),
                method("java/util/SortedSet", "first", [], object, interface: true),
                method("java/util/SortedSet", "last", [], object, interface: true),
                method("java/util/SortedSet", "headSet", [object], .reference("java/util/SortedSet", nullable: false), interface: true),
                method("java/util/SortedSet", "tailSet", [object], .reference("java/util/SortedSet", nullable: false), interface: true),
                method("java/util/SortedSet", "subSet", [object, object], .reference("java/util/SortedSet", nullable: false), interface: true),
            ]),
            ("java/lang/Void", """
            package java.lang
            class Void private constructor()
            """, 0x0011, "java/lang/Object", []),
            ("java/lang/reflect/Field", """
            package java.lang.reflect
            class Field private constructor() {
                var isAccessible: Boolean get() = false set(value) {}
                external fun setBoolean(receiver: Any?, value: Boolean)
                external fun setInt(receiver: Any?, value: Int)
            }
            """, 0x0011, "java/lang/reflect/AccessibleObject", [
                method("java/lang/reflect/Field", "isAccessible", [], .boolean),
                method("java/lang/reflect/Field", "setAccessible", [.boolean], .unit),
                method("java/lang/reflect/Field", "setBoolean", [object, .boolean], .unit),
                method("java/lang/reflect/Field", "setInt", [object, .int], .unit),
            ]),
            ("java/util/Locale", """
            package java.util
            open class Locale {
                val language: String get() = null!!
                companion object {
                    val ROOT: Locale get() = null!!
                    val US: Locale get() = null!!
                    val JAPAN: Locale get() = null!!
                    val JAPANESE: Locale get() = null!!
                    val ENGLISH: Locale get() = null!!
                    external fun getDefault(): Locale
                    external fun forLanguageTag(languageTag: String): Locale
                }
            }
            """, 0x0001, "java/lang/Object", [
                method("java/util/Locale", "getLanguage", [], .string),
                method("java/util/Locale", "getDefault", [], .reference("java/util/Locale", nullable: false), staticMember: true),
                method("java/util/Locale", "forLanguageTag", [.string], .reference("java/util/Locale", nullable: false), staticMember: true),
            ]),
            ("java/util/TreeMap", """
            package java.util
            open class TreeMap<K, V> : SortedMap<K, V> {
                constructor()
                constructor(comparator: kotlin.Comparator<in K>?)
                override fun comparator(): kotlin.Comparator<in K>? = null
                override fun firstKey(): K = null!!
                override fun lastKey(): K = null!!
                override fun headMap(toKey: K): SortedMap<K, V> = null!!
                override fun tailMap(fromKey: K): SortedMap<K, V> = null!!
                override fun subMap(fromKey: K, toKey: K): SortedMap<K, V> = null!!
                override val size: Int get() = 0
                override val keys: kotlin.collections.Set<K> get() = null!!
                override val values: kotlin.collections.Collection<V> get() = null!!
                override val entries: kotlin.collections.MutableSet<kotlin.collections.MutableMap.MutableEntry<K, V>> get() = null!!
                override fun get(key: K): V? = null
                override fun containsKey(key: K): Boolean = false
                override fun containsValue(value: V): Boolean = false
                override fun isEmpty(): Boolean = false
                override fun put(key: K, value: V): V? = null
                override operator fun set(key: K, value: V) {}
                override fun remove(key: K): V? = null
                override fun clear() {}
            }
            """, 0x0001, "java/util/AbstractMap", [
                method("java/util/TreeMap", "<init>", [], .reference("java/util/TreeMap", nullable: false)),
                method("java/util/TreeMap", "<init>", [.reference("java/util/Comparator", nullable: true)], .reference("java/util/TreeMap", nullable: false)),
                method("java/util/TreeMap", "put", [object, object], object),
                method("java/util/TreeMap", "subMap", [object, object], .reference("java/util/SortedMap", nullable: false)),
            ]),
            ("java/util/TreeSet", """
            package java.util
            open class TreeSet<E> : SortedSet<E> {
                constructor()
                constructor(comparator: kotlin.Comparator<in E>?)
                override fun comparator(): kotlin.Comparator<in E>? = null
                override fun first(): E = null!!
                override fun last(): E = null!!
                override fun headSet(toElement: E): SortedSet<E> = null!!
                override fun tailSet(fromElement: E): SortedSet<E> = null!!
                override fun subSet(fromElement: E, toElement: E): SortedSet<E> = null!!
                override val size: Int get() = 0
                override fun isEmpty(): Boolean = false
                override fun contains(element: E): Boolean = false
                override fun containsAll(elements: kotlin.collections.Collection<@UnsafeVariance E>): Boolean = false
                override fun iterator(): kotlin.collections.MutableIterator<E> = null!!
                override fun add(element: E): Boolean = false
                override fun addAll(elements: kotlin.collections.Collection<out E>): Boolean = false
                override fun remove(element: E): Boolean = false
                override fun removeAll(elements: kotlin.collections.Collection<out E>): Boolean = false
                override fun retainAll(elements: kotlin.collections.Collection<out E>): Boolean = false
                override fun clear() {}
            }
            """, 0x0001, "java/util/AbstractSet", [
                method("java/util/TreeSet", "<init>", [], .reference("java/util/TreeSet", nullable: false)),
                method("java/util/TreeSet", "<init>", [.reference("java/util/Comparator", nullable: true)], .reference("java/util/TreeSet", nullable: false)),
                method("java/util/TreeSet", "comparator", [], .reference("java/util/Comparator", nullable: true)),
                method("java/util/TreeSet", "first", [], object),
                method("java/util/TreeSet", "last", [], object),
                method("java/util/TreeSet", "headSet", [object], .reference("java/util/SortedSet", nullable: false)),
                method("java/util/TreeSet", "tailSet", [object], .reference("java/util/SortedSet", nullable: false)),
                method("java/util/TreeSet", "subSet", [object, object], .reference("java/util/SortedSet", nullable: false)),
            ]),
            ("java/util/HashSet", """
            package java.util
            open class HashSet<E> : kotlin.collections.MutableSet<E> {
                constructor()
                constructor(initialCapacity: Int)
                override val size: Int get() = 0
                override fun isEmpty(): Boolean = false
                override fun contains(element: E): Boolean = false
                override fun containsAll(elements: kotlin.collections.Collection<@UnsafeVariance E>): Boolean = false
                override fun iterator(): kotlin.collections.MutableIterator<E> = null!!
                override fun add(element: E): Boolean = false
                override fun addAll(elements: kotlin.collections.Collection<out E>): Boolean = false
                override fun remove(element: E): Boolean = false
                override fun removeAll(elements: kotlin.collections.Collection<out E>): Boolean = false
                override fun retainAll(elements: kotlin.collections.Collection<out E>): Boolean = false
                override fun clear() {}
            }
            """, 0x0001, "java/util/AbstractSet", [
                method("java/util/HashSet", "<init>", [], .reference("java/util/HashSet", nullable: false)),
                method("java/util/HashSet", "<init>", [.int], .reference("java/util/HashSet", nullable: false)),
                method("java/util/HashSet", "size", [], .int),
                method("java/util/HashSet", "isEmpty", [], .boolean),
                method("java/util/HashSet", "contains", [object], .boolean),
                method("java/util/HashSet", "containsAll", [.reference("java/util/Collection", nullable: false)], .boolean),
                method("java/util/HashSet", "iterator", [], .reference("java/util/Iterator", nullable: false)),
                method("java/util/HashSet", "add", [object], .boolean),
                method("java/util/HashSet", "addAll", [.reference("java/util/Collection", nullable: false)], .boolean),
                method("java/util/HashSet", "remove", [object], .boolean),
                method("java/util/HashSet", "removeAll", [.reference("java/util/Collection", nullable: false)], .boolean),
                method("java/util/HashSet", "retainAll", [.reference("java/util/Collection", nullable: false)], .boolean),
                method("java/util/HashSet", "clear", [], .unit),
            ]),
            ("java/util/Collections", """
            package java.util
            class Collections private constructor() {
                companion object { external fun <T> sort(list: kotlin.collections.List<T>, c: java.util.Comparator<in T>): Unit }
            }
            """, 0x0031, "java/lang/Object", [method("java/util/Collections", "sort", [.reference("java/util/List", nullable: false), comparator], .unit, staticMember: true)]),
            ("java/security/InvalidParameterException", """
            package java.security
            open class InvalidParameterException: kotlin.IllegalArgumentException {
                constructor(): super()
                constructor(msg: String?): super(msg)
            }
            """, 0x0001, "java/lang/IllegalArgumentException", [method("java/security/InvalidParameterException", "<init>", [], .reference("java/security/InvalidParameterException", nullable: false)), method("java/security/InvalidParameterException", "<init>", [.reference("java/lang/String", nullable: true)], .reference("java/security/InvalidParameterException", nullable: false))]),
            ("java/nio/charset/Charset", """
            package java.nio.charset
            abstract class Charset {
                fun name(): String = null!!
                companion object {
                    external fun forName(charsetName: String): Charset
                }
            }
            """, 0x0401, "java/lang/Object", [method("java/nio/charset/Charset", "name", [], .string), method("java/nio/charset/Charset", "forName", [.string], .reference("java/nio/charset/Charset", nullable: false), staticMember: true)]),
        ]
        for (name, source, flags, superclass, methods) in declarations {
            var info = JVMClassInfo(name: name, flags: flags, superclass: superclass, interfaces: [], methods: methods)
            if name == "java/lang/String" {
                info.fields = [JVMForeignField(name: "CASE_INSENSITIVE_ORDER", descriptor: "Ljava/util/Comparator;", access: 0x0019)]
            }
            if name == "java/util/Locale" {
                info.fields = ["ROOT", "US", "JAPAN", "JAPANESE", "ENGLISH"].map { JVMForeignField(name: $0, descriptor: "Ljava/util/Locale;", access: 0x0019) }
            }
            let path = "<kswiftk-jvm>/platform/" + name + ".kt"
            let file = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8), origin: .residualStdlib)
            sourceClasses[file] = info
            classes[name] = info
        }
        let randomName = "java/util/Random"
        if classes[randomName] == nil {
            let randomType = JVMValueType.reference(randomName, nullable: false)
            let methods = [
                method(randomName, "<init>", [], randomType),
                method(randomName, "<init>", [.long], randomType),
                method(randomName, "next", [.int], .int),
                method(randomName, "nextInt", [], .int),
                method(randomName, "nextInt", [.int], .int),
                method(randomName, "nextLong", [], .long),
                method(randomName, "nextBoolean", [], .boolean),
                method(randomName, "nextDouble", [], .double),
                method(randomName, "nextFloat", [], .float),
                method(randomName, "nextBytes", [.reference("[B", nullable: false)], .unit),
                method(randomName, "setSeed", [.long], .unit),
            ]
            let source = """
                package java.util
                open class Random {
                    constructor()
                    constructor(seed: Long)
                    protected open fun next(bits: Int): Int = 0
                    open fun nextInt(): Int = 0
                    open fun nextInt(bound: Int): Int = 0
                    open fun nextLong(): Long = 0L
                    open fun nextBoolean(): Boolean = false
                    open fun nextDouble(): Double = 0.0
                    open fun nextFloat(): Float = 0.0f
                    open fun nextBytes(bytes: ByteArray) {}
                    open fun setSeed(seed: Long) {}
                }
                """
            let info = JVMClassInfo(name: randomName, flags: 0x0001, superclass: "java/lang/Object",
                                    interfaces: ["java/io/Serializable"], methods: methods)
            let file = ctx.sourceManager.addFile(path: "<kswiftk-jvm>/platform/java/util/Random.kt",
                                                 contents: Data(source.utf8), origin: .residualStdlib)
            sourceClasses[file] = info
            classes[randomName] = info
        }
        let instantName = "java/time/Instant"
        if classes[instantName] == nil {
            let instantType = JVMValueType.reference(instantName, nullable: false)
            let methods = [
                method(instantName, "now", [], instantType, staticMember: true),
                method(instantName, "ofEpochSecond", [.long, .long], instantType, staticMember: true),
                method(instantName, "getEpochSecond", [], .long),
                method(instantName, "getNano", [], .int),
            ]
            let source = """
                package java.time
                class Instant private constructor() {
                    fun getEpochSecond(): Long = 0L
                    fun getNano(): Int = 0
                    companion object {
                        external fun now(): Instant
                        external fun ofEpochSecond(epochSecond: Long, nanoAdjustment: Long): Instant
                    }
                }
                """
            let info = JVMClassInfo(name: instantName, flags: 0x0011, superclass: "java/lang/Object",
                                    interfaces: [], methods: methods)
            let file = ctx.sourceManager.addFile(path: "<kswiftk-jvm>/platform/java/time/Instant.kt",
                                                 contents: Data(source.utf8), origin: .residualStdlib)
            sourceClasses[file] = info
            classes[instantName] = info
        }
        let durationName = "java/time/Duration"
        if classes[durationName] == nil {
            let durationType = JVMValueType.reference(durationName, nullable: false)
            let methods = [
                method(durationName, "ofSeconds", [.long, .long], durationType, staticMember: true),
                method(durationName, "getSeconds", [], .long),
                method(durationName, "getNano", [], .int),
            ]
            let source = """
                package java.time
                class Duration private constructor() {
                    fun getSeconds(): Long = 0L
                    fun getNano(): Int = 0
                    companion object {
                        external fun ofSeconds(seconds: Long, nanoAdjustment: Long): Duration
                    }
                }
                """
            let info = JVMClassInfo(name: durationName, flags: 0x0011, superclass: "java/lang/Object",
                                    interfaces: [], methods: methods)
            let file = ctx.sourceManager.addFile(path: "<kswiftk-jvm>/platform/java/time/Duration.kt",
                                                 contents: Data(source.utf8), origin: .residualStdlib)
            sourceClasses[file] = info
            classes[durationName] = info
        }
        // The shared frontend already declares File, its constructors and
        // path. Supply their JDK signatures even with no platform jar.
        let fileName = "java/io/File"
        if classes[fileName] == nil {
            let fileType = JVMValueType.reference(fileName, nullable: false)
            classes[fileName] = JVMClassInfo(name: fileName, flags: 0x0001, superclass: "java/lang/Object",
                                           interfaces: ["java/io/Serializable", "java/lang/Comparable"], methods: [
                method(fileName, "<init>", [.string], fileType),
                method(fileName, "<init>", [.string, .string], fileType),
                method(fileName, "<init>", [.reference(fileName, nullable: true), .string], fileType),
                method(fileName, "getPath", [], .string),
                method(fileName, "getAbsolutePath", [], .string),
                method(fileName, "mkdirs", [], .boolean),
            ])
        }
        let closeableName = "java/io/Closeable"
        if classes[closeableName] == nil {
            classes[closeableName] = JVMClassInfo(name: closeableName, flags: 0x0601, superclass: nil,
                                                interfaces: ["java/lang/AutoCloseable"], methods: [])
        }
        // `kotlin.io.path.Path` is a typealias over this JDK interface. Keep a
        // memberless fallback only when the classpath did not supply the real
        // interface; classpath classes keep their full member surface.
        if classes["java/nio/file/Path"] == nil {
            let info = JVMClassInfo(name: "java/nio/file/Path", flags: 0x0601, superclass: nil, interfaces: [], methods: [])
            let path = "<kswiftk-jvm>/platform/java/nio/file/Path.kt"
            let file = ctx.sourceManager.addFile(path: path, contents: Data("package java.nio.file\ninterface Path {}\n".utf8), origin: .residualStdlib)
            sourceClasses[file] = info
            classes[info.name] = info
        }

        // The generic Kotlin declaration provides the Java collection shape;
        // associate its implicit constructor with the real JDK owner so a
        // fully qualified `java.util.ArrayList()` call is emitted as `new`.
        let arrayListPath = "<kswiftk-jvm>/javaArrayList.kt"
        if let file = ctx.sourceManager.fileIDs().first(where: { ctx.sourceManager.path(of: $0) == arrayListPath }) {
            let info = classes["java/util/ArrayList"] ?? JVMClassInfo(
                name: "java/util/ArrayList",
                flags: 0x0001,
                superclass: "java/util/AbstractList",
                interfaces: ["java/util/List"],
                methods: [method("java/util/ArrayList", "<init>", [], .reference("java/util/ArrayList", nullable: false))]
            )
            sourceClasses[file] = info
            classes[info.name] = info
        }

        // The bundled `kotlin.Comparator` declaration erases to the JDK
        // interface (`builtinName` maps it to java/util/Comparator) and is
        // never lowered into a classfile. Binding its source file to the
        // platform import profile registers `compare` as an imported method
        // like other JDK-backed declarations, which SAM conversion and member
        // calls rely on.
        let comparatorPath = "<kswiftk-jvm>/comparator.kt"
        if let file = ctx.sourceManager.fileIDs().first(where: { ctx.sourceManager.path(of: $0) == comparatorPath }),
           let info = classes["java/util/Comparator"] {
            sourceClasses[file] = info
        }
    }

    func bindJDKFileMembers(in ctx: CompilationContext, sema: SemaModule) throws {
        guard let file = classes["java/io/File"] else { return }
        let path = ["java", "io", "File"].map(ctx.interner.intern)
        for name in ["<init>", "mkdirs"] {
            for symbol in sema.symbols.lookupAll(fqName: path + [ctx.interner.intern(name)]) {
                guard sema.symbols.symbol(symbol)?.declSite == nil,
                      let signature = sema.symbols.functionSignature(for: symbol) else { continue }
                let parameters = try signature.parameterTypes.map { try Self.type($0, sema: sema, ctx: ctx).descriptor }
                let result = name == "<init>" ? "V" : "Z"
                let descriptor = "(" + parameters.joined() + ")" + result
                methods[symbol] = file.methods.first { $0.name == name && $0.descriptor == descriptor }
            }
        }
        let inputStream = "java/io/InputStream"
        let inputPath = ["java", "io", "InputStream"].map(ctx.interner.intern)
        for name in ["available", "read"] {
            for symbol in sema.symbols.lookupAll(fqName: inputPath + [ctx.interner.intern(name)]) {
                guard sema.symbols.symbol(symbol)?.declSite == nil,
                      let signature = sema.symbols.functionSignature(for: symbol) else { continue }
                let parameters = try signature.parameterTypes.map { try Self.type($0, sema: sema, ctx: ctx) }
                let descriptor = "(" + parameters.map(\.descriptor).joined() + ")I"
                guard ["()I", "([B)I", "([BII)I"].contains(descriptor) else { continue }
                methods[symbol] = JVMForeignMethod(owner: inputStream, name: name, descriptor: descriptor,
                                                   parameters: parameters, result: .int, isStatic: false,
                                                   isInterface: false, isAbstract: false)
            }
        }
        for owner in ["java/io/OutputStream", "java/io/FileOutputStream", "java/io/Closeable", inputStream] {
            let names = owner.hasSuffix("OutputStream") ? ["flush", "close"] : ["close"]
            let path = owner.split(separator: "/").map { ctx.interner.intern(String($0)) }
            for name in names {
                for symbol in sema.symbols.lookupAll(fqName: path + [ctx.interner.intern(name)]) {
                    guard sema.symbols.symbol(symbol)?.declSite == nil,
                          sema.symbols.functionSignature(for: symbol)?.parameterTypes.isEmpty == true else { continue }
                    methods[symbol] = JVMForeignMethod(owner: owner, name: name, descriptor: "()V", parameters: [],
                                                       result: .unit, isStatic: false, isInterface: owner == "java/io/Closeable",
                                                       isAbstract: owner == "java/io/Closeable")
                }
            }
        }
    }
}
