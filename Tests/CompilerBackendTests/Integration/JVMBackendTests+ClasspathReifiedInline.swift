#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KUU-4614: `inline fun <reified T>` bodies read from a classpath JAR are
/// bytecode whose `reifiedOperationMarker` calls throw unless the call site
/// resolves them. Each case compares the program's output with the same
/// consumer compiled by kotlinc.
extension JVMBackendTests {
    private static let reifiedLibrary = """
    package fixture

    import kotlin.reflect.typeOf

    inline fun <reified T> reifiedTypeName(): String = T::class.toString()
    inline fun <reified T> isT(x: Any?): Boolean = x is T
    inline fun <reified T> isTN(x: Any?): Boolean = x is T?
    inline fun <reified T> notT(x: Any?): Boolean = x !is T
    inline fun <reified T> castT(x: Any?): T = x as T
    inline fun <reified T> castTN(x: Any?): T? = x as T?
    inline fun <reified T> safeCastT(x: Any?): T? = x as? T
    inline fun <reified T> arr(n: Int): Array<T?> = arrayOfNulls<T>(n)
    inline fun <reified T> typeStr(): String = typeOf<T>().toString()
    inline fun <reified T> jcls(): Class<T> = T::class.java
    inline fun <reified T, reified R> two(x: Any?): String = (x is T).toString() + R::class.toString()
    inline fun <reified T> withLambda(f: (Any?) -> Boolean, x: Any?): Boolean = f(x) && x is T
    inline fun <reified T> Any?.extIs(): Boolean = this is T
    inline fun <reified T> forwarded(x: Any?): Boolean = isT<T>(x)
    inline fun <reified T> notUsed(x: Int): Int = x + 1
    inline fun <reified T> arr2(n: Int): Array<Array<T>?> = arrayOfNulls<Array<T>>(n)
    inline fun <reified T> castArr(x: Any?): Array<T> = x as Array<T>
    fun plainLambda(): () -> Int = { 1 }
    fun template(x: Int): String = "v=$x"
    class Box { inline fun <reified T> member(x: Any?): Boolean = x is T }
    object Obj { inline fun <reified T> inObject(x: Any?): String = if (x is T) "yes" else "no" }
    """

    private static let reifiedConsumer = """
    import fixture.*

    inline fun <reified T> wrap(x: Any?): Boolean = isT<T>(x)

    private class Secret

    fun main() {
        println(reifiedTypeName<Secret>()); println(isT<Secret>(Secret())); println(isT<Secret>("x"))
        println(arr2<String>(2)::class.java.simpleName); println(arr2<Int>(1).size); println(castArr<String>(arrayOf("a")).size)
        println(plainLambda()()); println(template(3))
        println(wrap<String>("a")); println(wrap<Int>("a"))
        println(Box().takeIf { true }?.member<String>("a"))
        println(reifiedTypeName<String>()); println(reifiedTypeName<Int>()); println(reifiedTypeName<String?>())
        println(reifiedTypeName<List<String>>()); println(reifiedTypeName<Array<String>>()); println(reifiedTypeName<IntArray>())
        println(isT<String>("a")); println(isT<String>(1)); println(isT<Int>(1)); println(isT<Int>("x")); println(isT<String>(null))
        println(isT<List<String>>(listOf("a"))); println(isT<Array<String>>(arrayOf("a"))); println(isT<Any>(1))
        println(isTN<String>(null)); println(isTN<String>("a")); println(isTN<String>(1))
        println(isT<String?>(null)); println(isT<String?>("a")); println(isT<String?>(1))
        println(notT<String>("a")); println(notT<String>(1))
        println(castT<String>("a")); println(castT<Int>(5))
        try { castT<String>(null) } catch (e: NullPointerException) { println("npe: " + e.message) }
        try { castT<Int>("s") } catch (e: ClassCastException) { println("cce") }
        println(castTN<String>(null)); println(castTN<String>("b"))
        println(safeCastT<String>("a")); println(safeCastT<String>(1)); println(safeCastT<Int>(7)); println(safeCastT<String>(null))
        println(arr<String>(2).size); println(arr<Int>(3).size); println(arr<String>(1)::class.java.simpleName)
        println(typeStr<String>()); println(typeStr<Int>()); println(typeStr<String?>()); println(typeStr<List<String>>())
        println(typeStr<Map<String, List<Int>?>>()); println(typeStr<Array<Int>>()); println(typeStr<List<*>>())
        println(typeStr<Map<String, Map<String, List<Int>>>>())
        println(jcls<Int>()); println(jcls<String>()); println(jcls<Array<String>>())
        println(two<String, Int>("a")); println(two<Int, List<String>>("a"))
        println(withLambda<String>({ it != null }, "a")); println(withLambda<String>({ it != null }, 1))
        println("a".extIs<String>()); println(1.extIs<String>())
        println(Box().member<String>("a")); println(Box().member<Int>("a"))
        println(Obj.inObject<String>("a")); println(Obj.inObject<Int>("a"))
        println(forwarded<String>("a")); println(notUsed<String>(4))
    }
    """

    private func reifiedLibraryJar(_ root: URL, name: String, source: String) throws -> URL {
        try source.write(to: root.appendingPathComponent(name + ".kt"), atomically: true, encoding: .utf8)
        let built = try jvmTool("kotlinc", [name + ".kt", "-d", name + ".jar"], root: root)
        try #require(built.exitCode == 0, "\(built.stderr)")
        return root.appendingPathComponent(name + ".jar")
    }

    /// Output of the same consumer compiled and run by kotlinc.
    private func kotlincOutput(_ source: String, library: URL, runtime: String, root: URL) throws -> String {
        try source.write(to: root.appendingPathComponent("Oracle.kt"), atomically: true, encoding: .utf8)
        let built = try jvmTool("kotlinc", ["Oracle.kt", "-cp", library.path, "-d", "oracle.jar"], root: root)
        try #require(built.exitCode == 0, "\(built.stderr)")
        let run = try java(["-cp", root.appendingPathComponent("oracle.jar").path + ":" + library.path + ":" + runtime, "OracleKt"])
        try #require(run.exitCode == 0, "\(run.stderr)")
        return run.stdout
    }

    @Test
    func classpathReifiedInlineBodiesMatchKotlinc() throws {
        try withWorkspace { root in
            let library = try reifiedLibraryJar(root, name: "Reified", source: Self.reifiedLibrary)
            let runtime = try m11Runtime()
            let expected = try kotlincOutput(Self.reifiedConsumer, library: library, runtime: runtime, root: root)
            #expect(!expected.isEmpty)

            let compiled = try compile(Self.reifiedConsumer, root: root, mode: .jvmJar, classpath: [library.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let run = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + library.path + ":" + runtime, "HelloKt"])
            #expect(run.stdout == expected)
            #expect(run.stderr.isEmpty)
        }
    }

    @Test
    func classpathReifiedTypeNameRunsWithoutTheMarkerFailure() throws {
        try withWorkspace { root in
            let library = try reifiedLibraryJar(root, name: "Minimal", source: """
            package fixture
            inline fun <reified T> reifiedTypeName(): String = T::class.toString()
            """)
            let consumer = """
            import fixture.reifiedTypeName
            fun main() { println(reifiedTypeName<String>()) }
            """
            let compiled = try compile(consumer, root: root, mode: .jvmJar, classpath: [library.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let run = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + library.path + ":" + (try m11Runtime()), "HelloKt"])
            #expect(run.stdout == "class kotlin.String\n")
            #expect(run.stderr.isEmpty)
        }
    }

    /// The shape of `Json.encodeToString(value)`: a member reified function
    /// that forwards to another reified function through `typeOf<T>()`.
    @Test
    func classpathReifiedMemberForwardsTypeOfLikeSerializationJson() throws {
        try withWorkspace { root in
            let library = try reifiedLibraryJar(root, name: "Codec", source: """
            package fixture

            import kotlin.reflect.KType
            import kotlin.reflect.typeOf

            interface Serializer<T> { fun describe(): String }

            class TypeSerializer<T>(private val type: KType) : Serializer<T> {
                override fun describe(): String = type.toString()
            }

            inline fun <reified T> serializer(): Serializer<T> = TypeSerializer(typeOf<T>())

            open class Codec {
                fun <T> encode(serializer: Serializer<T>, value: T): String = serializer.describe() + "=" + value
                inline fun <reified T> encode(value: T): String = encode(serializer<T>(), value)
                companion object Default : Codec()
            }
            """)
            let consumer = """
            import fixture.Codec
            fun main() {
                println(Codec.encode(mapOf("a" to "b")))
                println(Codec.Default.encode(listOf(1, 2, 3)))
                println(Codec().encode("text"))
                println(Codec().encode<List<Map<String, Int?>>>(listOf()))
            }
            """
            let runtime = try m11Runtime()
            let expected = try kotlincOutput(consumer, library: library, runtime: runtime, root: root)
            let compiled = try compile(consumer, root: root, mode: .jvmJar, classpath: [library.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let run = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + library.path + ":" + runtime, "HelloKt"])
            #expect(run.stdout == expected)
            #expect(run.stderr.isEmpty)
        }
    }

    @Test
    func classpathReifiedBodiesWithUnsupportedShapesWarn() throws {
        try withWorkspace { root in
            let library = try reifiedLibraryJar(root, name: "Unsupported", source: """
            package fixture
            import kotlin.reflect.typeOf
            inline fun <reified T> lazyName(): () -> String = { T::class.toString() }
            inline fun <reified T, reified R> pick(f: Boolean): Any? = if (f) typeOf<T>() else typeOf<R>()
            """)
            let lambda = try compile("""
            import fixture.lazyName
            fun main() { println(lazyName<String>()()) }
            """, root: root, mode: .jvmJar, classpath: [library.path])
            #expect(lambda.1.contains { $0.severity == .warning && $0.message.contains("needs class reification") }, "\(lambda.1.map(\.message))")

            // Both typeOf results are merged as null in the stack map, which a KType cannot join.
            let merged = try compile("""
            import fixture.pick
            fun main() { println(pick<String, Int>(true)) }
            """, root: root, mode: .jvmJar, classpath: [library.path])
            #expect(merged.1.contains { $0.severity == .warning && $0.message.contains("stack map holds null values") }, "\(merged.1.map(\.message))")
        }
    }
}
#endif
