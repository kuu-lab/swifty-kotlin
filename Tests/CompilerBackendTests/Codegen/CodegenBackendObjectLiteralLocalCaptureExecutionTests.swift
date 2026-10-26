#if canImport(Testing)
// KSP-CAP-001: End-to-end execution tests for object-expression member
// function bodies capturing outer local variables/parameters. Property
// initializer capture already worked (inlined at the construction site);
// member function bodies are lowered as independent KIR functions, so the
// captured values must be threaded through instance fields instead.
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendObjectLiteralLocalCaptureExecutionTests {

    @Test
    func testObjectInApplyPropertyInitializerCapturesOuterInstance() throws {
        let source = """
        abstract class Y(val lambda: () -> Boolean) { abstract fun fun1(): Int }
        class X(initial: Int) {
            val num = initial
            val discarded: Int = 1.apply {
                object : Y({ true }) { override fun fun1(): Int = num }
            }
            val map: Int = 1.apply {
                val obj = object : Y({ true }) {
                    override fun fun1(): Int = num
                }
                if (obj.fun1() != 42) { val failure: Any? = null; failure!! }
            }
        }
        fun main() {
            val x = X(42)
            if (x.map != 1 || x.discarded != 1) { val failure: Any? = null; failure!! }
        }
        """
        try assertKotlinOutput(source, moduleName: "ObjectInApplyPropertyCapture", expected: "")
    }

    @Test
    func testLoweringUnpacksReifiedTypeTokensForObjectLiteralMembers() throws {
        let source = """
        inline fun <reified T> typeName(value: T): String = T::class.simpleName ?: "unknown"
        interface RefMaker<T> { fun reference(): (T) -> String }
        inline fun <reified T> objectMaker(): RefMaker<T> = object : RefMaker<T> {
            override fun reference(): (T) -> String = ::typeName
        }
        inline fun <reified T> nestedObjectMaker(): () -> RefMaker<T> = {
            object : RefMaker<T> { override fun reference(): (T) -> String = ::typeName }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ObjectLiteralReifiedTypeTokenCaptureKIR",
                emit: .kirDump,
                allowDefaultStdlibLibrary: false
            )
            try runToLowering(ctx)
            let module = try #require(ctx.kir)
            let references = findAllKIRFunctions(in: module).filter {
                ctx.interner.resolve($0.name) == "reference"
            }
            let tokenCapturingReferences = references.filter { function in
                extractCallees(from: function.body, interner: ctx.interner).contains("__kk_pair_first")
            }
            #expect(tokenCapturingReferences.count == 2)
            for function in tokenCapturingReferences {
                let callees = extractCallees(from: function.body, interner: ctx.interner)
                #expect(callees.contains("__kk_pair_second"))
                let classTokenIndex = try #require(callees.firstIndex(of: "__kk_pair_first"))
                let componentTokenIndex = try #require(callees.firstIndex(of: "__kk_pair_second"))
                #expect(classTokenIndex < componentTokenIndex)
            }
        }
    }

    @Test
    func testCodegenObjectLiteralCapturesBothReifiedTypeTokens() throws {
        let source = """
        inline fun <reified T> typeName(value: T): String = T::class.simpleName ?: "unknown"
        interface RefMaker<T> { fun reference(): (T) -> String }
        inline fun <reified T> objectMaker(): RefMaker<T> = object : RefMaker<T> {
            override fun reference(): (T) -> String = ::typeName
        }
        inline fun <reified T> nestedObjectMaker(): () -> RefMaker<T> = {
            object : RefMaker<T> { override fun reference(): (T) -> String = ::typeName }
        }
        fun main() {
            println(objectMaker<String>().reference()("object"))
            println(nestedObjectMaker<String>()().reference()("nested-object"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralReifiedTypeTokenCaptureExecution",
            expected: "String\nString\n"
        )
    }

    @Test(arguments: ["make", "inherited", "local"])
    func testMemberExtensionLocalNominalsCaptureInheritedDispatchOwner(_ method: String) throws {
        let source = """
        open class OBase(protected val off: Int) {
            protected fun helper(): Int = 3
        }
        class ODerived : OBase(10) {
            fun Int.make(): Int {
                val o = object {
                    fun read(): Int = off
                    fun read2(): Int = helper()
                }
                return this + o.read() + o.read2()
            }
            fun Int.inherited(): Int {
                val o = object : OBase(1) {
                    fun read(): Int = off + this@ODerived.off
                }
                return this + o.read()
            }
            fun Int.local(): Int {
                class Local { fun read(): Int = off + helper() }
                return this + Local().read()
            }
            fun use() {
                println(2.\(method)())
            }
        }
        fun main() { ODerived().use() }
        """
        try assertKotlinOutput(
            source,
            moduleName: "MemberExtensionLocalNominalDispatchOwner",
            expected: method == "inherited" ? "13\n" : "15\n"
        )
    }

    @Test
    func testCodegenObjectLiteralMemberFunctionCapturesValParameter() throws {
        let source = """
        interface Greeter {
            fun greet(): String
        }

        fun makeGreeter(name: String): Greeter {
            return object : Greeter {
                override fun greet(): String {
                    return "Hello, " + name
                }
            }
        }

        fun main() {
            val g = makeGreeter("World")
            println(g.greet())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralCaptureValParamExecution",
            expected: "Hello, World\n"
        )
    }

    // KUU-2111: an outer class property read by an anonymous object's inline
    // property initializer must use the enclosing instance, not the new object.
    @Test
    func testCodegenObjectLiteralPropertyInitializerCapturesOuterImmutableProperty() throws {
        let source = """
        interface T {
            fun result(): String
        }
        class A(val x: String) {
            fun foo(): T = object : T {
                val bar = x
                override fun result(): String = bar
            }
        }
        fun main() {
            println(A("OK").foo().result())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralPropertyInitializerCapturesOuterProperty",
            expected: "OK\n"
        )
    }

    @Test
    func testCodegenObjectLiteralMemberFunctionCallsEnclosingPrivateMember() throws {
        let source = """
        class ConstGetter(val value: Int) {
            private fun fetch(index: Int): Int = value + index
            fun call(): Int {
                val o = object : Any() {
                    fun get(): Int = fetch(1)
                }
                return o.get()
            }
        }

        fun main() {
            println(ConstGetter(41).call())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralEnclosingPrivateMemberCallExecution",
            expected: "42\n"
        )
    }

    @Test
    func testCodegenObjectLiteralIteratorMutatesOuterReceiverProperties() throws {
        let source = """
        class CountingSeq : Sequence<Int> {
            var pulls = 0
            var marker = 41

            override fun iterator(): Iterator<Int> = object : Iterator<Int> {
                private var cur = 0
                override fun hasNext(): Boolean { pulls++; return cur < 5 }
                override fun next(): Int { cur++; return cur }
            }
        }

        fun main() {
            val s = CountingSeq()
            val it = s.iterator()
            println(it.hasNext())
            println(it.next())
            println(it.next())
            println("pulls=${s.pulls} marker=${s.marker}")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralIteratorMutatesOuterReceiverProperties",
            expected: """
            true
            1
            2
            pulls=1 marker=41
            """ + "\n"
        )
    }

    @Test
    func testCodegenObjectLiteralMemberFunctionCapturesAndMutatesVarAcrossCalls() throws {
        let source = """
        interface Counter {
            fun increment(): Int
        }

        fun makeCounter(start: Int): Counter {
            var count = start
            return object : Counter {
                override fun increment(): Int {
                    count = count + 1
                    return count
                }
            }
        }

        fun main() {
            val c = makeCounter(10)
            println(c.increment())
            println(c.increment())
            println(c.increment())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralCaptureVarMutationExecution",
            expected:
                """
                11
                12
                13
                """
                + "\n"
        )
    }

    // Verified against real kotlinc (kotlinc-jvm): a bare reference inside
    // the member function binds to the captured outer local, not the object
    // literal's own member of the same name -- the outer local wins, and the
    // object's own member would only be reachable via explicit `this.x`.
    @Test
    func testCodegenObjectLiteralCapturedOuterLocalShadowsOwnPropertyOfSameName() throws {
        let source = """
        interface Box {
            fun value(): Int
        }

        fun makeBox(): Box {
            val x = 100
            return object : Box {
                val x = 5
                override fun value(): Int {
                    return x
                }
            }
        }

        fun main() {
            println(makeBox().value())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralCaptureShadowingExecution",
            expected: "100\n"
        )
    }

    @Test
    func testCodegenObjectLiteralMemberFunctionCapturesFunctionTypedParameter() throws {
        let source = """
        interface Provider {
            fun provide(): Int
        }

        fun makeProvider(block: () -> Int): Provider {
            return object : Provider {
                override fun provide(): Int {
                    return block()
                }
            }
        }

        fun main() {
            val p = makeProvider { 42 }
            println(p.provide())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralCaptureLambdaParamExecution",
            expected: "42\n"
        )
    }

    // KUU-3181 (JetBrains classes/kt1918): `recv.fn()` / `recv?.fn()` where
    // `fn` is an outer function-typed parameter of extension-function type
    // binds `fn`'s symbol on the member-call expr through
    // `CallableValueCallBinding.extensionCallableExpr`, not a `.nameRef` child.
    // `CaptureAnalyzer` never read that binding, so the object literal's (and
    // a local class's) capture set missed `fn` and the invoke lowered to a raw
    // `symbolRef` of a parameter not in scope — "Invalid function value".
    @Test
    func testCodegenObjectLiteralMemberFunctionInvokesCapturedExtensionLambda() throws {
        let source = """
        interface Foo {
            fun xyzzy(x: Any?): String
        }
        class Bar

        fun buildFoo(bar: Bar.() -> Unit): Foo = object : Foo {
            override fun xyzzy(x: Any?): String {
                (x as? Bar)?.bar()
                return "OK"
            }
        }

        fun main() {
            println(buildFoo({ println("invoked") }).xyzzy(Bar()))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralSafeCallExtensionLambdaCaptureExecution",
            expected: "invoked\nOK\n"
        )
    }

    @Test
    func testCodegenLocalNominalMemberFunctionInvokesCapturedExtensionLambda() throws {
        let source = """
        interface Foo {
            fun run(x: Any?): String
        }
        class Bar

        fun buildFoo(bar: Bar.() -> Unit): Foo {
            class LocalFoo : Foo {
                override fun run(x: Any?): String {
                    val b = Bar()
                    b.bar()
                    val nb: Bar? = Bar()
                    nb?.bar()
                    return "OK"
                }
            }
            return LocalFoo()
        }

        fun main() {
            println(buildFoo({ println("invoked") }).run(Bar()))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "LocalNominalExtensionLambdaCaptureExecution",
            expected: "invoked\ninvoked\nOK\n"
        )
    }

    @Test
    func testCodegenObjectLiteralMultipleInstancesCaptureIndependentMutableState() throws {
        // Two separate makeCounter() calls must not share the same captured
        // `count` box -- each object literal instance captures its own.
        let source = """
        interface Counter {
            fun increment(): Int
        }

        fun makeCounter(start: Int): Counter {
            var count = start
            return object : Counter {
                override fun increment(): Int {
                    count = count + 1
                    return count
                }
            }
        }

        fun main() {
            val a = makeCounter(0)
            val b = makeCounter(100)
            println(a.increment())
            println(b.increment())
            println(a.increment())
            println(b.increment())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralCaptureIndependentInstancesExecution",
            expected:
                """
                1
                101
                2
                102
                """
                + "\n"
        )
    }

    // KSP-441: for-in over a generic object-expression Sequence/Iterator pipeline
    // whose `map` is inferred from the receiver's element type.
    @Test
    func testCodegenForInOverGenericObjectExpressionSequence() throws {
        let source = """
        interface Seq<out T> {
            operator fun iterator(): Iterator<T>
        }

        fun <T, R> Seq<T>.mapManual(transform: (T) -> R): Seq<R> {
            val source = this
            val t = transform
            return object : Seq<R> {
                override fun iterator(): Iterator<R> {
                    val src = source
                    val tr = t
                    val it = src.iterator()
                    return object : Iterator<R> {
                        override fun hasNext(): Boolean = it.hasNext()
                        override fun next(): R = tr(it.next())
                    }
                }
            }
        }

        fun makeSeq(limit: Int): Seq<Int> = object : Seq<Int> {
            override fun iterator(): Iterator<Int> {
                val l = limit
                return object : Iterator<Int> {
                    var count = 0
                    override fun hasNext(): Boolean = count < l
                    override fun next(): Int {
                        val r = count
                        count++
                        return r
                    }
                }
            }
        }

        fun main() {
            val mapped = makeSeq(3).mapManual { it * 10 }
            for (i in mapped) {
                println(i)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForInGenericObjectExpressionSequenceExecution",
            expected:
                """
                0
                10
                20
                """
                + "\n"
        )
    }

    // KSP-441: trailing-lambda type inference for a member function of a
    // user-defined generic class must substitute the receiver's type args.
    @Test
    func testCodegenGenericClassMemberTrailingLambdaTypeInference() throws {
        let source = """
        class Box<T>(val value: T) {
            fun <R> map(transform: (T) -> R): Box<R> = Box(transform(value))
        }

        fun main() {
            val b = Box(3).map { it * 10 }
            println(b.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericClassMemberTrailingLambdaInferenceExecution",
            expected: "30\n"
        )
    }

    // KSP-CAP-001 (follow-up): a *bare* (unqualified) read of an enclosing
    // class's mutable property from inside an object literal's member
    // function previously crashed with `KSWIFTK-RUNTIME-0001:
    // kk_array_get_inbounds precondition failed`. Such a read resolves
    // through plain lexical scope lookup rather than
    // `resolveImplicitReceiverMember`, so it never set
    // `implicitReceiverMemberNames` and the generic field-offset read
    // fallback in ExprLowerer+ControlFlowAndBlocks.swift used the object
    // literal's own receiver with the enclosing class's field offset instead
    // of walking the already-captured outer-receiver chain.
    @Test
    func testCodegenObjectLiteralMemberFunctionBareReadsOuterMutableProperty() throws {
        let source = """
        class Outer(val tag: String) {
            var counter: Int = 5
            fun make(): Int {
                val obj = object {
                    fun show(): Int {
                        return counter
                    }
                }
                return obj.show()
            }
        }

        fun main() {
            val o = Outer("hello")
            println(o.make())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralBareReadOuterMutablePropertyExecution",
            expected: "5\n"
        )
    }

    // KSP-CAP-001 (follow-up): a bare *write-only* reference (no read of the
    // same property anywhere in the object literal's body) was invisible to
    // `CaptureAnalyzer.collectCapturedOuterSymbols`, which only recorded
    // `.nameRef` reads -- so `capturesMutableOuterProperty` never fired, no
    // capture slot was allocated, and the write landed on the object
    // literal's own (much smaller) instance, throwing an unhandled
    // out-of-bounds exception.
    @Test
    func testCodegenObjectLiteralMemberFunctionBareWriteOnlyToOuterMutableProperty() throws {
        let source = """
        class Outer(val tag: String) {
            var counter: Int = 5
            fun make(): Int {
                val obj = object {
                    fun bump() {
                        counter = 42
                    }
                }
                obj.bump()
                return this.counter
            }
        }

        fun main() {
            val o = Outer("hello")
            println(o.make())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralBareWriteOnlyOuterMutablePropertyExecution",
            expected: "42\n"
        )
    }

    // Companion to the write-only case above, for `+=` instead of `=`.
    @Test
    func testCodegenObjectLiteralMemberFunctionBareCompoundAssignOnlyToOuterMutableProperty() throws {
        let source = """
        class Outer(val tag: String) {
            var counter: Int = 5
            fun make(): Int {
                val obj = object {
                    fun bump() {
                        counter += 1
                    }
                }
                obj.bump()
                return this.counter
            }
        }

        fun main() {
            val o = Outer("hello")
            println(o.make())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralBareCompoundAssignOnlyOuterMutablePropertyExecution",
            expected: "6\n"
        )
    }
}
#endif
