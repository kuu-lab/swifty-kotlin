@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ForwardObjectPropertyInferenceTests {
    @Test(arguments: [false, true])
    func objectSupertypeResolvesAcrossFiles(declarationsFirst: Bool) throws {
        let use = """
        package sample
        fun consumeString(): Sink<String> = completion
        """
        let declarations = """
        package sample
        interface Sink<in T> { fun consume(value: T): Int }
        internal val completion = object : Sink<Any?> {
            override fun consume(value: Any?): Int = 42
        }
        """
        let sources = declarationsFirst ? [declarations, use] : [use, declarations]
        try expectNoErrors(sources: sources)
    }

    @Test
    func objectBodyWaitsForDeclarationOrderDependencies() throws {
        let source = """
        interface Sink<in T> { fun consume(value: T): Int }
        fun use(): Sink<String> = completion
        fun makeAnswer() = 42
        private val answer = makeAnswer()
        private val completion = object : Sink<Any?> {
            override fun consume(value: Any?): Int = answer
        }
        """
        try expectNoErrors(sources: [source])
    }

    @Test(arguments: ["completion.answer()", "completion.answer"])
    func objectSpecificMembersRetainDemandInference(access: String) throws {
        let member = access.hasSuffix("()") ? "fun answer(): Int = 42" : "val answer = 42"
        let source = """
        fun typedUse(): Int = inferredUse()
        fun inferredUse() = \(access)
        private val completion = object {
            \(member)
        }
        """
        try expectNoErrors(sources: [source])
    }

    @Test
    func predeclaredObjectStillChecksItsBodyOnce() throws {
        let source = """
        interface Sink<in T> { fun consume(value: T): Int }
        fun use(): Sink<String> = completion
        private val completion = object : Sink<Any?> {
            override fun consume(value: Any?): Int = "wrong"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "\(errors.map { "\($0.code): \($0.message)" })")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0469")
        }
    }

    @Test
    func objectLiteralGetterReadsLaterInferredLazyProperty() throws {
        let source = """
        interface Lazy<out T> {
            operator fun getValue(thisRef: Any?, property: Any?): T
        }
        class LazyImpl<T>(private val value: T) : Lazy<T> {
            override fun getValue(thisRef: Any?, property: Any?): T = value
        }
        fun <T> lazy(initializer: () -> T): Lazy<T> = LazyImpl(initializer())

        fun demo(): Int = object {
            val first get() = later
            val later by lazy { 41 }
        }.first
        """
        try expectNoErrors(sources: [source])
    }

    @Test
    func objectLiteralLazyPrecheckWaitsForExplicitMemberReceiver() throws {
        let source = """
        interface Lazy<out T> {
            operator fun getValue(thisRef: Any?, property: Any?): T
        }
        class LazyImpl<T>(private val value: T) : Lazy<T> {
            override fun getValue(thisRef: Any?, property: Any?): T = value
        }
        fun <T> lazy(initializer: () -> T): Lazy<T> = LazyImpl(initializer())

        fun demo(): Int = object {
            val base get() = if (true) 41 else 42
            val result by lazy { this.base }
        }.result
        """
        try expectNoErrors(sources: [source])
    }

    @Test
    func objectLiteralLazyPrecheckValidatesDelegateArguments() throws {
        let source = """
        interface Lazy<out T> {
            operator fun getValue(thisRef: Any?, property: Any?): T
        }
        class LazyImpl<T>(private val value: T) : Lazy<T> {
            override fun getValue(thisRef: Any?, property: Any?): T = value
        }
        enum class LazyThreadSafetyMode { NONE, SYNCHRONIZED }
        fun <T> lazy(initializer: () -> T): Lazy<T> = LazyImpl(initializer())
        fun <T> lazy(mode: LazyThreadSafetyMode, initializer: () -> T): Lazy<T> = LazyImpl(initializer())

        fun demo(): Int = object {
            val mode get() = if (true) LazyThreadSafetyMode.NONE else LazyThreadSafetyMode.SYNCHRONIZED
            val result by lazy(mode = mode) { 41 }
        }.result
        """
        try expectNoErrors(sources: [source])
    }

    private func expectNoErrors(sources: [String]) throws {
        try withTemporaryFiles(contents: sources) { paths in
            let context = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(context)
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")
        }
    }
}
