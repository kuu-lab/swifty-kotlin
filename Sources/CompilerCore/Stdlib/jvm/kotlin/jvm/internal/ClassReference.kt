package kotlin.jvm.internal
import kotlin.reflect.*
import kotlin.reflect.jvm.internal.*

class ClassReference<T>(val jClass: java.lang.Class<T>): KClass<T> {
    private val metadata: RuntimeMetadata get() = RuntimeMetadata(jClass)
    private val flags: Int get() = metadata.root.number(1)
    override val simpleName: String? get() {
        if (__jvmClassIsAnonymous(jClass)) return null
        val name = __jvmClassName(jClass)
        val mapped = kotlinName(name)
        return if (mapped == null) __jvmClassSimpleName(jClass) else mapped.substringAfterLast(".")
    }
    override val qualifiedName: String? get() {
        if (__jvmClassIsAnonymous(jClass) || __jvmClassIsLocal(jClass)) return null
        val name = __jvmClassName(jClass)
        val simple = kotlinName(name)
        return if (simple != null) "kotlin.$simple" else name.replace("$", ".")
    }
    override val annotations: List<Annotation> get() = visibleAnnotations(jClass)
    override val members: Collection<KCallable<*>> get() {
        val result = mutableListOf<KCallable<*>>()
        collectMembers(jClass, false, result, mutableSetOf<String>(), mutableSetOf<Any>())
        return result
    }
    override val constructors: Collection<KFunction<T>> get() {
        val result = mutableListOf<KFunction<T>>()
        for (node in metadata.constructors()) result.add(RuntimeFunction(jClass, "<init>", metadata.signature(node, true), null, false) as KFunction<T>)
        return result
    }
    override val nestedClasses: Collection<KClass<*>> get() {
        val result = mutableListOf<KClass<*>>()
        for (nested in __jvmDeclaredClasses(jClass)) result.add(ClassReference(nested as java.lang.Class<Any>))
        return result
    }
    override val objectInstance: T? get() {
        if ((flags and 448) != 320 && !isCompanion) return null
        for (memberField in __jvmDeclaredFields(jClass)) if (__jvmFieldName(memberField) == "INSTANCE") return __jvmFieldGet(memberField, null) as T?
        if (isCompanion) {
            val outerName = __jvmClassName(jClass).substringBeforeLast("$")
            val outer = __jvmLoadClass(outerName, false, __jvmClassLoader(jClass))
            for (memberField in __jvmDeclaredFields(outer)) if (__jvmFieldName(memberField) == __jvmClassSimpleName(jClass)) return __jvmFieldGet(memberField, null) as T?
        }
        return null
    }
    override val isFinal: Boolean get() = if (metadata.root.bytes.isEmpty()) (__jvmClassModifiers(jClass) and 16) != 0 else (flags and 48) == 0
    override val isOpen: Boolean get() = (flags and 48) == 16
    override val isAbstract: Boolean get() = if (metadata.root.bytes.isEmpty()) (__jvmClassModifiers(jClass) and 1024) != 0 else (flags and 48) == 32
    override val isSealed: Boolean get() = (flags and 48) == 48
    override val isData: Boolean get() = (flags and 1024) != 0
    override val isInner: Boolean get() = (flags and 512) != 0
    override val isCompanion: Boolean get() = (flags and 448) == 384
    override val isFun: Boolean get() = (flags and 16384) != 0
    override val isValue: Boolean get() = (flags and 8192) != 0
    override fun isInstance(value: Any?): Boolean {
        if (!__jvmClassIsPrimitive(jClass)) return __jvmClassInstance(jClass, value)
        return when (__jvmClassName(jClass)) {
            "int" -> value is Int
            "long" -> value is Long
            "byte" -> value is Byte
            "short" -> value is Short
            "char" -> value is Char
            "float" -> value is Float
            "double" -> value is Double
            "boolean" -> value is Boolean
            else -> false
        }
    }
    override fun equals(other: Any?): Boolean = other is ClassReference<*> && normalizedClass(jClass) == normalizedClass(other.jClass)
    override fun hashCode(): Int = normalizedClass(jClass).hashCode()
    override fun toString(): String {
        val name = __jvmClassName(jClass)
        val mapped = kotlinName(name)
        return "class ${if (mapped == null) name else "kotlin.$mapped"}"
    }
}
// Return types can be covariant; JVM bridges identify erased overrides too.
private fun memberKey(signature: String): String = signature.substringBefore(")") + ")"
private fun isInheritedMember(flags: Int): Boolean {
    val visibility = flags and 14
    return visibility != 2 && visibility != 8 && visibility != 10
}
private fun collectMembers(owner: Any, inherited: Boolean, result: MutableList<KCallable<*>>, signatures: MutableSet<String>, visited: MutableSet<Any>) {
    if (!visited.add(owner)) return
    val metadata = RuntimeMetadata(owner)
    for (node in metadata.functions()) {
        val flags = node.number(9, node.number(1))
        val signature = metadata.signature(node)
        if ((!inherited || isInheritedMember(flags)) && signatures.add(memberKey(signature))) {
            result.add(RuntimeFunction(owner, metadata.string(node.number(2)), signature, null, false))
        }
    }
    for (node in metadata.properties()) {
        val flags = node.number(11, node.number(1))
        val signature = metadata.propertySignature(node, 3)
        if ((!inherited || isInheritedMember(flags)) && signatures.add(memberKey(signature))) {
            result.add(propertyReference(owner, metadata.string(node.number(2)), signature, (flags and 256) != 0))
        }
    }
    // Bridges are not separate Kotlin members, but suppress overridden ancestors.
    for (method in __jvmDeclaredMethods(owner)) {
        if ((__jvmExecutableModifiers(method) and 10) == 0) signatures.add(memberKey(__jvmMethodName(method) + executableDescriptor(method)))
    }
    val parent = __jvmClassSuperclass(owner)
    if (parent != null) collectMembers(parent, true, result, signatures, visited)
    for (parentInterface in __jvmClassInterfaces(owner)) collectMembers(parentInterface, true, result, signatures, visited)
}

private fun kotlinName(name: String): String? = when (name) {
    "int", "java.lang.Integer" -> "Int"
    "long", "java.lang.Long" -> "Long"
    "byte", "java.lang.Byte" -> "Byte"
    "short", "java.lang.Short" -> "Short"
    "char", "java.lang.Character" -> "Char"
    "float", "java.lang.Float" -> "Float"
    "double", "java.lang.Double" -> "Double"
    "boolean", "java.lang.Boolean" -> "Boolean"
    "java.lang.String" -> "String"
    "java.lang.Object" -> "Any"
    "java.lang.Throwable" -> "Throwable"
    "java.lang.Number" -> "Number"
    "java.lang.CharSequence" -> "CharSequence"
    "java.lang.Comparable" -> "Comparable"
    "java.lang.Enum" -> "Enum"
    "java.lang.annotation.Annotation" -> "Annotation"
    "java.lang.Cloneable" -> "Cloneable"
    "java.lang.Iterable" -> "collections.Iterable"
    "java.util.Iterator" -> "collections.Iterator"
    "java.util.ListIterator" -> "collections.ListIterator"
    "java.util.Collection" -> "collections.Collection"
    "java.util.List" -> "collections.List"
    "java.util.Set" -> "collections.Set"
    "java.util.Map" -> "collections.Map"
    "java.util.Map\$Entry" -> "collections.Map.Entry"
    "[I" -> "IntArray"
    "[J" -> "LongArray"
    "[B" -> "ByteArray"
    "[S" -> "ShortArray"
    "[C" -> "CharArray"
    "[F" -> "FloatArray"
    "[D" -> "DoubleArray"
    "[Z" -> "BooleanArray"
    else -> if (name.startsWith("[")) "Array" else if (name.startsWith("kotlin.jvm.functions.Function")) name.substringAfterLast(".") else null
}

private fun normalizedClass(type: Any): Any {
    if (!__jvmClassIsPrimitive(type)) return type
    val name = when (__jvmClassName(type)) {
        "int" -> "java.lang.Integer"
        "long" -> "java.lang.Long"
        "byte" -> "java.lang.Byte"
        "short" -> "java.lang.Short"
        "char" -> "java.lang.Character"
        "float" -> "java.lang.Float"
        "double" -> "java.lang.Double"
        "boolean" -> "java.lang.Boolean"
        "void" -> "java.lang.Void"
        else -> __jvmClassName(type)
    }
    return __jvmLoadClass(name, false, null)
}
