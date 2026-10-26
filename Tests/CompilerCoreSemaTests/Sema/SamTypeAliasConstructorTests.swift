#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct SamTypeAliasConstructorTests {
    private func context(_ source: String) throws -> CompilationContext {
        let ctx = makeCompilationContext(inputs: ["/sam-typealias-constructor.kt"], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: "/sam-typealias-constructor.kt", contents: Data(source.utf8))
        try runSema(ctx)
        return ctx
    }

    @Test
    func fixedAndGenericFunInterfaceAliasesAreSamConstructors() throws {
        let ctx = try context("""
        fun interface KRunnable { fun invoke(): String }
        fun interface KConsumer<T> { fun accept(value: T): T }
        typealias KRunnableAlias = KRunnable
        typealias StringConsumer = KConsumer<String>
        typealias ConsumerAlias<T> = KConsumer<T>

        fun runnable(): String = KRunnableAlias { "OK" }.invoke()
        fun consumer(): String = StringConsumer { it }.accept("OK")
        fun explicitConsumerAlias(): String = ConsumerAlias<String> { it }.accept("OK")
        fun inferredConsumerAlias(): String = ConsumerAlias { value: String -> value }.accept("OK")
        """)

        #expect(!ctx.diagnostics.hasError, "Expected fun-interface aliases to provide SAM context: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
