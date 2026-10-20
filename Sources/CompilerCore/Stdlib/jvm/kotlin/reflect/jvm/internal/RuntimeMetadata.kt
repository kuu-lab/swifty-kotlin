package kotlin.reflect.jvm.internal
import kotlin.jvm.internal.*
import kotlin.jvm.java

internal class ProtoField(val key: Int, val number: Int, val bytes: List<Int>)
internal class ProtoReader(val bytes: List<Int>) {
    var offset = 0
    fun readInt(): Int {
        var value = 0
        var shift = 0
        while (offset < bytes.size && shift < 35) {
            val next = bytes[offset++]
            value = value or ((next and 127) shl shift)
            if (next < 128) return value
            shift += 7
        }
        throw IllegalStateException("Malformed Kotlin metadata")
    }
    fun take(count: Int): List<Int> {
        if (count < 0 || count > bytes.size - offset) throw IllegalStateException("Malformed Kotlin metadata length")
        val result = mutableListOf<Int>()
        var index = 0
        while (index < count) { result.add(bytes[offset++]); index++ }
        return result
    }
}
internal class Proto(val bytes: List<Int>) {
    fun fields(): List<ProtoField> {
        val result = mutableListOf<ProtoField>()
        val reader = ProtoReader(bytes)
        while (reader.offset < bytes.size) {
            val tag = reader.readInt()
            val key = tag ushr 3
            val wire = tag and 7
            if (wire == 0) result.add(ProtoField(key, reader.readInt(), emptyList()))
            else if (wire == 2) result.add(ProtoField(key, 0, reader.take(reader.readInt())))
            else if (wire == 1) reader.take(8)
            else if (wire == 5) reader.take(4)
            else throw IllegalStateException("Unsupported Kotlin metadata wire type")
        }
        return result
    }
    fun number(key: Int, defaultValue: Int = 0): Int {
        for (field in fields()) if (field.key == key) return field.number
        return defaultValue
    }
    fun child(key: Int): Proto {
        for (field in fields()) if (field.key == key) return Proto(field.bytes)
        return Proto(emptyList())
    }
    fun children(key: Int): List<Proto> {
        val result = mutableListOf<Proto>()
        for (field in fields()) if (field.key == key) result.add(Proto(field.bytes))
        return result
    }
    fun packed(key: Int): List<Int> {
        val result = mutableListOf<Int>()
        for (field in fields()) if (field.key == key) {
            if (field.bytes.isEmpty()) result.add(field.number)
            else {
                val reader = ProtoReader(field.bytes)
                while (reader.offset < field.bytes.size) result.add(reader.readInt())
            }
        }
        return result
    }
    fun has(key: Int): Boolean { for (field in fields()) if (field.key == key) return true; return false }
}
internal fun decodeMetadata(data: Array<String>): List<Int> {
    val result = mutableListOf<Int>()
    for (part in data) for (character in part) result.add(character.code and 255)
    if (result.isEmpty()) return result
    if (result[0] == 0) return result.drop(1)
    if (data[0][0].code == 65535) result.removeAt(0)
    val decoded = mutableListOf<Int>()
    var buffer = 0
    var bits = 0
    for (value in result) {
        buffer = buffer or (((value + 127) and 127) shl bits)
        bits += 7
        if (bits >= 8) { decoded.add(buffer and 255); buffer = buffer ushr 8; bits -= 8 }
    }
    return decoded
}
internal class RuntimeMetadata(val owner: Any) {
    private val annotation: kotlin.Metadata? = __jvmClassAnnotation(owner, kotlin.Metadata::class.java) as kotlin.Metadata?
    val strings: Array<String> = if (annotation == null) arrayOf<String>() else annotation!!.d2
    val isClass: Boolean = annotation != null && annotation!!.k == 1
    private val table: Proto = readTable()
    val root: Proto = readRoot()
    private fun readTable(): Proto {
        if (annotation == null) return Proto(emptyList())
        val bytes = decodeMetadata(annotation!!.d1)
        if (bytes.isEmpty()) return Proto(emptyList())
        val reader = ProtoReader(bytes)
        return Proto(reader.take(reader.readInt()))
    }
    private fun readRoot(): Proto {
        if (annotation == null) return Proto(emptyList())
        val bytes = decodeMetadata(annotation!!.d1)
        if (bytes.isEmpty()) return Proto(emptyList())
        val reader = ProtoReader(bytes)
        reader.take(reader.readInt())
        return Proto(reader.take(bytes.size - reader.offset))
    }
    fun string(index: Int): String {
        var value = if (index >= 0 && index < strings.size) strings[index] else ""
        var start = 0
        for (record in table.children(1)) {
            val count = record.number(1, 1)
            if (index >= start && index < start + count) {
                if (record.has(6)) {
                    val bytes = record.child(6).bytes
                    val raw = ByteArray(bytes.size)
                    var position = 0
                    while (position < bytes.size) { raw[position] = bytes[position].toByte(); position++ }
                    value = __jvmUtf8String(raw, "UTF-8")
                } else if (record.has(2)) {
                    val predefined = record.number(2)
                    if (predefined >= 0 && predefined < predefinedStrings.size) value = predefinedStrings[predefined]
                }
                val substring = record.packed(4)
                if (substring.size == 2 && substring[0] >= 0 && substring[1] <= value.length) value = value.substring(substring[0], substring[1])
                val replace = record.packed(5)
                if (replace.size == 2) value = value.replace(replace[0].toChar(), replace[1].toChar())
                val operation = record.number(3)
                if (operation == 1) value = value.replace("$", ".")
                if (operation == 2 && value.length >= 2) value = value.substring(1, value.length - 1).replace("$", ".")
                return value
            }
            start += count
        }
        return value
    }
    fun type(node: Proto, inlineKey: Int, idKey: Int): Proto {
        if (node.has(inlineKey)) return node.child(inlineKey)
        if (!node.has(idKey)) return Proto(emptyList())
        val types = if (node.has(30)) node.child(30) else root.child(30)
        val index = node.number(idKey)
        val values = types.children(1)
        if (index < 0 || index >= values.size) return Proto(emptyList())
        val result = values[index]
        if (index < types.number(2, Int.MAX_VALUE)) return result
        val bytes = mutableListOf<Int>()
        for (value in result.bytes) bytes.add(value)
        bytes.add(24); bytes.add(1)
        return Proto(bytes)
    }
    private fun descriptor(type: Proto, returns: Boolean = false, boxed: Boolean = false): String {
        if (!type.has(6)) return "Ljava/lang/Object;"
        val name = string(type.number(6))
        if (name == "kotlin/Unit" && returns && type.number(3) == 0) return "V"
        if (name == "kotlin/Array") {
            val arguments = type.children(2)
            return "[" + if (arguments.isEmpty()) "Ljava/lang/Object;" else descriptor(this.type(arguments[0], 2, 3), false, true)
        }
        val primitive = when (name) {
            "kotlin/Int" -> "I"; "kotlin/Long" -> "J"; "kotlin/Byte" -> "B"; "kotlin/Short" -> "S"
            "kotlin/Char" -> "C"; "kotlin/Float" -> "F"; "kotlin/Double" -> "D"; "kotlin/Boolean" -> "Z"
            else -> ""
        }
        if (!primitive.isEmpty() && (boxed || type.number(3) != 0)) return when (primitive) {
            "I" -> "Ljava/lang/Integer;"; "J" -> "Ljava/lang/Long;"; "B" -> "Ljava/lang/Byte;"; "S" -> "Ljava/lang/Short;"
            "C" -> "Ljava/lang/Character;"; "F" -> "Ljava/lang/Float;"; "D" -> "Ljava/lang/Double;"; else -> "Ljava/lang/Boolean;"
        }
        if (!primitive.isEmpty()) return primitive
        return classDescriptor(loadMetadataType(name, owner))
    }
    fun signature(node: Proto, constructor: Boolean = false): String {
        val signature = node.child(100)
        val name = if (signature.has(1)) string(signature.number(1)) else if (constructor) "<init>" else string(node.number(2))
        if (signature.has(2)) return name + string(signature.number(2))
        var parameters = ""
        if (!constructor && (node.has(5) || node.has(8))) parameters += descriptor(type(node, 5, 8))
        for (parameter in node.children(if (constructor) 2 else 6)) parameters += descriptor(type(parameter, 3, 5))
        if (!constructor && (node.number(9, node.number(1)) and 8192) != 0) return name + "(" + parameters + "Lkotlin/coroutines/Continuation;)Ljava/lang/Object;"
        return name + "(" + parameters + ")" + if (constructor) "V" else descriptor(type(node, 3, 7), true)
    }
    fun functions(): List<Proto> = root.children(if (isClass) 9 else 3)
    fun properties(): List<Proto> = root.children(if (isClass) 10 else 4)
    fun constructors(): List<Proto> = root.children(8)
    fun callable(signature: String): Proto {
        for (node in functions()) if (signature(node) == signature) return node
        for (node in constructors()) if (signature(node, true) == signature) return node
        return Proto(emptyList())
    }
    fun property(name: String): Proto {
        for (node in properties()) if (string(node.number(2)) == name) return node
        return Proto(emptyList())
    }
    fun propertySignature(node: Proto, key: Int): String {
        val properties = node.child(100)
        if (key == 2 && !properties.has(key)) return ""
        val signature = properties.child(key)
        val propertyName = string(node.number(2))
        val booleanName = propertyName.startsWith("is") && propertyName.length > 2 && propertyName[2] >= 'A' && propertyName[2] <= 'Z'
        val stem = if (booleanName) propertyName.substring(2) else if (propertyName.isEmpty()) propertyName else propertyName.substring(0, 1).uppercase() + propertyName.substring(1)
        val name = if (signature.has(1)) string(signature.number(1)) else if (key == 4) "set" + stem else if (booleanName) propertyName else "get" + stem
        if (signature.has(2)) return name + string(signature.number(2))
        var parameters = if (node.has(5) || node.has(10)) descriptor(type(node, 5, 10)) else ""
        if (key == 4) parameters += descriptor(type(node, 3, 9))
        return name + "(" + parameters + ")" + if (key == 2 || key == 4) "V" else descriptor(type(node, 3, 9))
    }

}
internal fun classDescriptor(type: Any): String {
    val name = __jvmClassName(type)
    return when (name) {
        "void" -> "V"
        "boolean" -> "Z"
        "byte" -> "B"
        "short" -> "S"
        "char" -> "C"
        "int" -> "I"
        "long" -> "J"
        "float" -> "F"
        "double" -> "D"
        else -> if (name.startsWith("[")) name.replace(".", "/") else "L" + name.replace(".", "/") + ";"
    }
}
internal fun executableDescriptor(method: Any, constructor: Boolean = false): String {
    var descriptor = "("
    for (parameter in __jvmExecutableParams(method)) descriptor += classDescriptor(parameter)
    return descriptor + ")" + if (constructor) "V" else classDescriptor(__jvmMethodReturn(method))
}
internal fun findMethod(owner: Any, signature: String): Any {
    var current: Any? = owner
    while (current != null) {
        for (method in __jvmDeclaredMethods(current!!)) {
            if (__jvmMethodName(method) + executableDescriptor(method) == signature) { __jvmSetAccessible(method, true); return method }
        }
        current = __jvmClassSuperclass(current!!)
    }
    throw IllegalStateException("Missing reflected JVM method: $signature")
}
internal fun expandAnnotations(annotations: Array<Annotation>): List<Annotation> {
    val result = mutableListOf<Annotation>()
    val repeatableType = __jvmLoadClass("java.lang.annotation.Repeatable", false, null)
    for (annotation in annotations) {
        if (annotation is kotlin.Metadata) continue
        val type = __jvmAnnotationType(annotation)
        var expanded = false
        for (method in __jvmDeclaredMethods(type)) {
            if (__jvmMethodName(method) != "value") continue
            val returnType = __jvmMethodReturn(method)
            if (!__jvmClassIsArray(returnType)) continue
            val component = __jvmComponentType(returnType)
            if (!__jvmClassIsAnnotation(component)) continue
            val repeatable = __jvmClassAnnotation(component, repeatableType)
            if (repeatable == null || __jvmRepeatableContainer(repeatable) != type) continue
            __jvmSetAccessible(method, true)
            val contents = __jvmMethodInvoke(method, annotation, arrayOf<Any?>()) as Array<Annotation>
            for (value in contents) result.add(value)
            expanded = true
        }
        if (!expanded) result.add(annotation)
    }
    return result
}
internal fun visibleAnnotations(element: Any): List<Annotation> = expandAnnotations(__jvmAnnotations(element))
internal fun loadMetadataType(name: String, owner: Any): Any = when (name) {
    "kotlin/Any" -> Any::class.java
    "kotlin/String" -> String::class.java
    "kotlin/Int" -> Int::class.java
    "kotlin/Long" -> Long::class.java
    "kotlin/Byte" -> Byte::class.java
    "kotlin/Short" -> Short::class.java
    "kotlin/Char" -> Char::class.java
    "kotlin/Float" -> Float::class.java
    "kotlin/Double" -> Double::class.java
    "kotlin/Boolean" -> Boolean::class.java
    "kotlin/Unit" -> Unit::class.java
    else -> {
        val runtimeName = when (name) {
            "kotlin/Nothing" -> "java.lang.Void"
            "kotlin/Throwable" -> "java.lang.Throwable"
            "kotlin/Number" -> "java.lang.Number"
            "kotlin/CharSequence" -> "java.lang.CharSequence"
            "kotlin/Comparable" -> "java.lang.Comparable"
            "kotlin/Enum" -> "java.lang.Enum"
            "kotlin/Annotation" -> "java.lang.annotation.Annotation"
            "kotlin/Cloneable" -> "java.lang.Cloneable"
            "kotlin/Array" -> "[Ljava.lang.Object;"
            "kotlin/IntArray" -> "[I"
            "kotlin/LongArray" -> "[J"
            "kotlin/ByteArray" -> "[B"
            "kotlin/ShortArray" -> "[S"
            "kotlin/CharArray" -> "[C"
            "kotlin/FloatArray" -> "[F"
            "kotlin/DoubleArray" -> "[D"
            "kotlin/BooleanArray" -> "[Z"
            "kotlin/collections/Iterable", "kotlin/collections/MutableIterable" -> "java.lang.Iterable"
            "kotlin/collections/Iterator", "kotlin/collections/MutableIterator" -> "java.util.Iterator"
            "kotlin/collections/ListIterator", "kotlin/collections/MutableListIterator" -> "java.util.ListIterator"
            "kotlin/collections/Collection", "kotlin/collections/MutableCollection" -> "java.util.Collection"
            "kotlin/collections/List", "kotlin/collections/MutableList" -> "java.util.List"
            "kotlin/collections/Set", "kotlin/collections/MutableSet" -> "java.util.Set"
            "kotlin/collections/Map", "kotlin/collections/MutableMap" -> "java.util.Map"
            "kotlin/collections/Map.Entry", "kotlin/collections/MutableMap.MutableEntry" -> "java.util.Map\$Entry"
            else -> if (name.startsWith("kotlin/Function") && name != "kotlin/Function") name.replace("kotlin/", "kotlin.jvm.functions.") else name.replace(".", "$").replace("/", ".")
        }
        __jvmLoadClass(runtimeName, false, __jvmClassLoader(owner))
    }
}

// JVM metadata predefined string indices are part of the Kotlin metadata format.
private val predefinedStrings: List<String> = listOf(
    "kotlin/Any",
    "kotlin/Nothing",
    "kotlin/Unit",
    "kotlin/Throwable",
    "kotlin/Number",
    "kotlin/Byte",
    "kotlin/Double",
    "kotlin/Float",
    "kotlin/Int",
    "kotlin/Long",
    "kotlin/Short",
    "kotlin/Boolean",
    "kotlin/Char",
    "kotlin/CharSequence",
    "kotlin/String",
    "kotlin/Comparable",
    "kotlin/Enum",
    "kotlin/Array",
    "kotlin/ByteArray",
    "kotlin/DoubleArray",
    "kotlin/FloatArray",
    "kotlin/IntArray",
    "kotlin/LongArray",
    "kotlin/ShortArray",
    "kotlin/BooleanArray",
    "kotlin/CharArray",
    "kotlin/Cloneable",
    "kotlin/Annotation",
    "kotlin/collections/Iterable",
    "kotlin/collections/MutableIterable",
    "kotlin/collections/Collection",
    "kotlin/collections/MutableCollection",
    "kotlin/collections/List",
    "kotlin/collections/MutableList",
    "kotlin/collections/Set",
    "kotlin/collections/MutableSet",
    "kotlin/collections/Map",
    "kotlin/collections/MutableMap",
    "kotlin/collections/Map.Entry",
    "kotlin/collections/MutableMap.MutableEntry",
    "kotlin/collections/Iterator",
    "kotlin/collections/MutableIterator",
    "kotlin/collections/ListIterator",
    "kotlin/collections/MutableListIterator"
)
