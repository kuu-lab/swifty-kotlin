@testable import CompilerCore
import Testing

@Suite
struct KClassSingletonPropertyTests {
    @Test func typedSingletonAndSealedSubclassProperties() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        object Obj { val value = 42 }
        sealed class Root
        class Child : Root()
        sealed interface SealedIface
        fun <T : Any> instance(k: KClass<T>): T? = k.objectInstance
        fun singleton(): Obj? = Obj::class.objectInstance
        fun subclasses(): List<KClass<out Root>> = Root::class.sealedSubclasses
        fun projected(k: KClass<in Obj>): Any? = k.objectInstance
        fun erased(k: KClass<*>): Any? = k.objectInstance
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-ABSTRACT" })
    }

    @Test func contravariantSingletonCannotBeReadAsNarrowType() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        fun wrong(k: KClass<in String>): String? = k.objectInstance
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }

    @Test func userTypeOfStillShadowsTheStdlibIntrinsic() throws {
        let ctx = makeContextFromSource("""
        fun <T> typeOf(): Int = 7
        fun main() { println(typeOf<Int>()) }
        """, allowDefaultStdlibLibrary: false)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(callees.contains("typeOf"))
        #expect(!callees.contains("kk_typeof"))
    }
}
