#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct AnonymousObjectExposureTests {
    @Test(arguments: ["public", "internal", "private"])
    func inferredFunctionExposesAnonymousMembersOnlyWhenPrivate(visibility: String) throws {
        try withTemporaryFile(contents: """
        \(visibility) fun make() = object { val value = 42 }
        fun use(): Int = make().value
        """) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(context.diagnostics.hasError == (visibility != "private"))
        }
    }

    @Test(arguments: ["public", "private"])
    func nestedAnonymousTypesFollowTheAPIsVisibility(visibility: String) throws {
        for (body, access) in [("Box(object { val answer = 42 })", "make().value.answer"), ("{ object { val answer = 42 } }", "make()().answer")] {
            try withTemporaryFile(contents: """
            class Box<T>(val value: T)
            \(visibility) fun make() = \(body)
            fun use(): Int = \(access)
            """) { path in
                let context = makeCompilationContext(inputs: [path], includeStdlib: false)
                try runSema(context)
                #expect(context.diagnostics.hasError == (visibility != "private"))
            }
        }
    }

    @Test
    func publicPropertyAndFunctionExposeTheirGenericSupertype() throws {
        try withTemporaryFile(contents: """
        interface Getter<T> { fun get(): T }
        fun <T> make(value: T) = object: Getter<T> { override fun get(): T = value }
        class Holder { val value = object: Getter<Int> { override fun get(): Int = 42 } }
        fun use(): Int = make(Holder().value.get()).get()
        """) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }
}
#endif
