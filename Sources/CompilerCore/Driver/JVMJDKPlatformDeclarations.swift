import Foundation

extension JVMClasspathIndex {
    /// A small source profile preserves Kotlin generics at JDK boundaries.
    /// Bodies remain in the JDK; no java.* classes are emitted into our stdlib.
    func injectJDKPlatformDeclarations(into ctx: CompilationContext) throws {
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let comparator: JVMValueType = .reference("java/util/Comparator", nullable: false)
        let extractor: JVMValueType = .reference("java/util/function/ToIntFunction", nullable: false)
        func method(_ owner: String, _ name: String, _ parameters: [JVMValueType], _ result: JVMValueType, staticMember: Bool = false, interface: Bool = false) -> JVMForeignMethod {
            JVMForeignMethod(owner: owner, name: name, descriptor: "(" + parameters.map(\.descriptor).joined() + ")" + (name == "<init>" ? "V" : result.descriptor), parameters: parameters, result: result, isStatic: staticMember, isInterface: interface, isAbstract: interface && !staticMember)
        }
        let objectArray = JVMValueType.reference("[Ljava/lang/Object;", nullable: false)
        let nullableObjectArray = JVMValueType.reference("[Ljava/lang/Object;", nullable: true)
        var arraysMethods = [
            method("java/util/Arrays", "copyOf", [objectArray, .int], objectArray, staticMember: true),
            method("java/util/Arrays", "equals", [nullableObjectArray, nullableObjectArray], .boolean, staticMember: true),
            method("java/util/Arrays", "hashCode", [nullableObjectArray], .int, staticMember: true),
            method("java/util/Arrays", "toString", [nullableObjectArray], .string, staticMember: true),
            method("java/util/Arrays", "deepEquals", [nullableObjectArray, nullableObjectArray], .boolean, staticMember: true),
            method("java/util/Arrays", "deepHashCode", [nullableObjectArray], .int, staticMember: true),
            method("java/util/Arrays", "deepToString", [nullableObjectArray], .string, staticMember: true),
            method("java/util/Arrays", "sort", [objectArray], .unit, staticMember: true),
            method("java/util/Arrays", "sort", [objectArray, .int, .int], .unit, staticMember: true),
            method("java/util/Arrays", "binarySearch", [objectArray, .int, .int, .reference("java/lang/Object", nullable: true)], .int, staticMember: true),
        ]
        var arraysSource = """
            package java.util
            class Arrays private constructor() {
                companion object {
                    external fun <T> copyOf(a: Array<out T>, newLength: Int): Array<T>
                    external fun equals(a: Array<out Any?>?, b: Array<out Any?>?): Boolean
                    external fun hashCode(a: Array<out Any?>?): Int
                    external fun toString(a: Array<out Any?>?): String
                    external fun deepEquals(a: Array<out Any?>?, b: Array<out Any?>?): Boolean
                    external fun deepHashCode(a: Array<out Any?>?): Int
                    external fun deepToString(a: Array<out Any?>?): String
                    external fun sort(a: Array<out Any?>): Unit
                    external fun sort(a: Array<out Any?>, fromIndex: Int, toIndex: Int): Unit
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
            arraysMethods.append(method("java/util/Arrays", "equals", [nullableArray, nullableArray], .boolean, staticMember: true))
            arraysMethods.append(method("java/util/Arrays", "hashCode", [nullableArray], .int, staticMember: true))
            arraysMethods.append(method("java/util/Arrays", "toString", [nullableArray], .string, staticMember: true))
            arraysMethods.append(method("java/util/Arrays", "copyOf", [array, .int], array, staticMember: true))
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
                    external fun getProperty(propertyName: String): String?
                    external fun getProperty(propertyName: String, defaultValue: String): String
                    external fun arraycopy(src: Any?, srcPos: Int, dest: Any?, destPos: Int, length: Int): Unit
                }
            }
            """, 0x0011, "java/lang/Object", [
                method("java/lang/System", "getProperty", [.string], .reference("java/lang/String", nullable: true), staticMember: true),
                method("java/lang/System", "getProperty", [.string, .string], .reference("java/lang/String", nullable: false), staticMember: true),
                method("java/lang/System", "arraycopy", [object, .int, object, .int, .int], .unit, staticMember: true),
            ]),
            ("java/lang/StackTraceElement", """
            package java.lang
            class StackTraceElement private constructor()
            """, 0x0011, "java/lang/Object", []),
            ("java/lang/Integer", """
            package java.lang
            class Integer private constructor() {
                companion object {
                    external fun parseInt(value: String): Int
                    external fun parseInt(value: String, radix: Int): Int
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
                }
            }
            """, 0x0011, "java/lang/Object", [
                method("java/lang/Character", "isDigit", [.char], .boolean, staticMember: true),
                method("java/lang/Character", "isDigit", [.int], .boolean, staticMember: true),
            ]),
            ("java/util/Arrays", arraysSource, 0x0031, "java/lang/Object", arraysMethods),
            ("java/util/function/ToIntFunction", """
            package java.util.function
            fun interface ToIntFunction<T> { fun applyAsInt(value: T): Int }
            """, 0x0601, "java/lang/Object", [method("java/util/function/ToIntFunction", "applyAsInt", [object], .int, interface: true)]),
            ("java/util/Comparator", """
            package java.util
            fun interface Comparator<T> {
                fun compare(first: T, second: T): Int
                companion object {
                    external fun <T> comparingInt(keyExtractor: java.util.function.ToIntFunction<in T>): java.util.Comparator<T>
                }
            }
            """, 0x0601, "java/lang/Object", [method("java/util/Comparator", "compare", [object, object], .int, interface: true), method("java/util/Comparator", "comparingInt", [extractor], comparator, staticMember: true, interface: true)]),
            ("java/util/Collections", """
            package java.util
            class Collections private constructor() {
                companion object { external fun <T> sort(list: List<T>, c: java.util.Comparator<in T>): Unit }
            }
            """, 0x0031, "java/lang/Object", [method("java/util/Collections", "sort", [.reference("java/util/List", nullable: false), comparator], .unit, staticMember: true)]),
            ("java/security/InvalidParameterException", """
            package java.security
            open class InvalidParameterException: kotlin.IllegalArgumentException {
                constructor(): super()
                constructor(msg: String?): super(msg)
            }
            """, 0x0001, "java/lang/IllegalArgumentException", [method("java/security/InvalidParameterException", "<init>", [], .reference("java/security/InvalidParameterException", nullable: false)), method("java/security/InvalidParameterException", "<init>", [.reference("java/lang/String", nullable: true)], .reference("java/security/InvalidParameterException", nullable: false))]),
        ]
        for (name, source, flags, superclass, methods) in declarations {
            let info = JVMClassInfo(name: name, flags: flags, superclass: superclass, interfaces: [], methods: methods)
            let path = "<kswiftk-jvm>/platform/" + name + ".kt"
            let file = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8), origin: .residualStdlib)
            sourceClasses[file] = info
            classes[name] = info
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
    }
}
