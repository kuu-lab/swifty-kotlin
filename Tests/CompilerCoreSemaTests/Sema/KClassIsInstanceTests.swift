@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct KClassIsInstanceTests {
    @Test func starReceiverIssue1988() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        fun main() {
            val k: KClass<*> = Int::class
            println(k.isInstance(42))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func projectedAndTypedReceiverContracts() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        import kotlin.reflect.cast
        import kotlin.reflect.safeCast
        fun star(k: KClass<*>): Boolean = k.isInstance(42)
        fun typed(k: KClass<Int>): Boolean = k.isInstance(null)
        fun projected(k: KClass<out Number>): Boolean = k.isInstance("other")
        fun contravariant(k: KClass<in Int>): Boolean = k.isInstance(42)
        fun castStar(k: KClass<*>): Any = k.cast(42)
        fun safeCastStar(k: KClass<*>): Any? = k.safeCast(null)
        fun castTyped(k: KClass<Int>): Int = k.cast(42)
        fun safeCastTyped(k: KClass<Int>): Int? = k.safeCast("other")
        fun castContravariant(k: KClass<in Int>): Any = k.cast(42)
        fun name(k: KClass<*>): String? = k.simpleName
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func typedCastCannotReturnAnUnrelatedType() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        import kotlin.reflect.cast
        fun wrong(k: KClass<Int>): String = k.cast(42)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }

    @Test func starReceiverCannotConsumeTheCapturedArgument() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        fun <T : Any> KClass<T>.consume(value: T) {}
        fun wrong(k: KClass<*>) { k.consume(42) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: ["*", "in Int"])
    func projectedCastCannotReturnANarrowType(projection: String) throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        import kotlin.reflect.cast
        fun wrong(k: KClass<\(projection)>): Int = k.cast(42)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }

    @Test func explicitTypeArgumentCannotReplaceAStarCapture() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        fun <T : Any> KClass<T>.read(): T? = null
        fun wrong(k: KClass<*>): Any? = k.read<Any>()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func userExtensionCanReadAProjectedReceiver() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        fun <T : Any> KClass<T>.readValue(): T? = null
        fun star(k: KClass<*>): Any? = k.readValue()
        fun projected(k: KClass<in Int>): Any? = k.readValue()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func starReceiverDoesNotSatisfyANarrowerGenericBound() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        fun <T : Number> KClass<T>.numeric(): Boolean = true
        fun wrong(k: KClass<*>): Boolean = k.numeric()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func starReceiverCannotConsumeThroughADependentBound() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        fun <T : Any, U : T> KClass<T>.consumeIndirect(value: U) {}
        fun wrong(k: KClass<*>) { k.consumeIndirect(42) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func starCaptureCannotBeReified() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        inline fun <reified T : Any> KClass<T>.reifiedRead(): Boolean = true
        fun wrong(k: KClass<*>): Boolean = k.reifiedRead()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: ["out Number", "in Int"])
    func projectedCaptureCannotBeReified(projection: String) throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        inline fun <reified T : Any> KClass<T>.reifiedRead(): Boolean = true
        fun wrong(k: KClass<\(projection)>): Boolean = k.reifiedRead()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-REIFIED" })
    }

    @Test func concreteAndReifiedForwardedArgumentsCanBeReified() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        inline fun <reified T : Any> KClass<T>.reifiedRead(): Boolean = true
        fun ok(k: KClass<Int>): Boolean = k.reifiedRead()
        inline fun <reified U : Any> fwd(k: KClass<U>): Boolean = k.reifiedRead()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func starCaptureCannotWidenAnInvariantResult() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        class Box<T>
        fun <T : Any> KClass<T>.boxed(): Box<T>? = null
        fun wrong(k: KClass<*>): Box<Any>? = k.boxed()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func starCaptureCannotReplaceAnOwnerTypeArgument() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        class Holder<T : Any> {
            fun KClass<T>.readOnly(): Boolean = true
        }
        fun Holder<Any>.wrong(k: KClass<*>): Boolean = k.readOnly()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
