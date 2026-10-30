#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct AnonymousExtensionFunctionTests {
    @Test
    func anonymousExtensionFunctionResolvesReceiverFunctionType() throws {
        try withTemporaryFile(contents: """
        fun probe(): Int.() -> String = fun Int.(): String { return "OK" }
        fun control(): Int.() -> String = { "OK" }
        """) { path in
            let context = makeCompilationContext(inputs: [path])
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }

    @Test
    func extensionFunctionFakeOverrideOriginalFixtureSema() throws {
        try withTemporaryFile(contents: """
        open class Base {
            open val <T> (Int.() -> T).bar: T
                get() = this(1)
            open fun <T> (Int.() -> T).foo(): T { return this(1) }
        }

        class A : Base() {
            fun test(): String {
                val a = fun Int.(): String { return "O" }.bar
                val b = fun Int.(): String { return "K" }.foo()
                return a + b
            }
        }

        fun box(): String {
            return A().test()
        }
        """) { path in
            let context = makeCompilationContext(inputs: [path])
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }
}
#endif
