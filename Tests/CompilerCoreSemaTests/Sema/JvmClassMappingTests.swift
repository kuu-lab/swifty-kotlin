@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct JvmClassMappingTests {
    @Test(arguments: ["", "import kotlin.jvm.kotlin\nimport kotlin.jvm.javaPrimitiveType\nimport kotlin.jvm.javaObjectType", "import kotlin.jvm.*"])
    func preservesMappingContracts(imports: String) throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        \(imports)
        fun mapped(type: java.lang.Class<String>): KClass<String> = type.kotlin
        fun primitive(type: KClass<Int>): java.lang.Class<Int>? = type.javaPrimitiveType
        fun objectType(type: KClass<Int>): java.lang.Class<Int> = type.javaObjectType
        fun <T : Any> generic(type: java.lang.Class<T>): KClass<T> = type.kotlin
        fun <T : Any> genericPrimitive(type: KClass<T>): java.lang.Class<T>? = type.javaPrimitiveType
        fun <T : Any> genericObject(type: KClass<T>): java.lang.Class<T> = type.javaObjectType
        fun javaType(type: java.lang.Class<String>): java.lang.Class<String> = type
        fun javaVoid(value: Void): java.lang.Void = value
        fun primitiveVoid(type: KClass<Void>): java.lang.Class<Void>? = type.javaPrimitiveType
        fun kotlinType(type: KClass<Int>): KClass<Int> = type
        fun objectClass(value: String): java.lang.Class<String> = value.javaClass
        fun main() {}
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun wrong(type: java.lang.Class<String>): KClass<Int> = type.kotlin",
        "fun wrong(type: KClass<Int>): java.lang.Class<Int> = type.javaPrimitiveType",
        "fun wrong(type: KClass<Int>): java.lang.Class<String>? = type.javaPrimitiveType",
        "fun wrong(type: KClass<Int>): java.lang.Class<String> = type.javaObjectType",
        "fun wrong(value: String) = value.kotlin",
        "fun wrong(value: String) = value.javaPrimitiveType",
        "fun wrong(value: String) = value.javaObjectType",
        "fun wrong(type: java.lang.Class<String>?) = type.kotlin",
        "fun wrong(type: KClass<Int>?) = type.javaPrimitiveType",
        "fun wrong(type: KClass<Int>?) = type.javaObjectType",
        "fun wrong(type: java.lang.Class<String?>) = type.kotlin",
    ])
    func rejectsInvalidMapping(source: String) throws {
        let ctx = makeContextFromSource("import kotlin.reflect.KClass\n" + source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, Comment(rawValue: source))
    }
}
