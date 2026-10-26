#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct InnerClassOuterReceiverCallTests {
    private func context(_ source: String) throws -> CompilationContext {
        let path = "/inner-class-typealias-constructor.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(ctx)
        return ctx
    }

    @Test func topLevelTypeAliasToInnerClassResolvesThroughOuterReceiver() throws {
        let ctx = try context("""
        class Outer { inner class Child(val value: String) }
        typealias ChildAlias = Outer.Child
        fun box(): String {
            val outer = Outer()
            return outer.ChildAlias("OK").value
        }
        """)

        #expect(!ctx.diagnostics.hasError,
                "Expected a typealias to an inner class to resolve through its outer receiver, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func genericInnerTypeAliasesMapOuterAndInnerArguments() throws {
        let ctx = try context("""
        class Foo<T> {
            inner class Inner(val p: String)
            inner class Inner2<T2>
        }
        typealias InnerAlias<K> = Foo<K>.Inner
        typealias InnerAlias2<K, K2> = Foo<K>.Inner2<K2>
        typealias InnerAlias3<K, K2> = Foo<K2>.Inner2<K>
        fun use(foo: Foo<String>): String {
            val inner = foo.InnerAlias("OK")
            foo.InnerAlias2<String, Int>()
            foo.InnerAlias3<Int, String>()
            val make = Foo<String>::InnerAlias
            return make(foo, "OK").p + inner.p
        }
        """)

        #expect(!ctx.diagnostics.hasError,
                "Expected generic inner typealias constructors and references to resolve, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func typeAliasConstructorReferencesResolveFromOuterTypeAndScope() throws {
        let ctx = try context("""
        class C {
            inner class Inner
            inner class Inner2<K>
            fun create() {
                TA()
                TA2<String>()
                val callable = ::TA
                callable()
            }
        }
        typealias TA = C.Inner
        typealias TA2<K> = C.Inner2<K>
        fun use() {
            val c = C()
            c.TA()
            c.TA2<String>()
            val callable = C::TA
            callable(c)
        }
        """)

        #expect(!ctx.diagnostics.hasError,
                "Expected inner constructor aliases in scoped and unbound references to resolve, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func unqualifiedCallResolvesToOuterClassMember() throws {
        try withSemaContext("""
        class Outer(val value: Int) {
            fun fetch(index: Int): Int = value + index
            inner class Inner {
                fun compute(): Int = fetch(1)
            }
        }
        """) { ctx in
            #expect(!ctx.diagnostics.hasError,
                    "Expected unqualified outer member call to resolve, got: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test func nestedClassCanCallEnclosingObjectMembers() throws {
        try withSemaContext("""
        object Owner {
            fun answer(): Int = 1
            fun answerFromBody(): Int = answer()
            class Nested {
                fun answerFromOwner(): Int = answer()
                fun qualifiedAnswer(): Int = Owner.answer()
            }
        }
        """) { ctx in
            #expect(!ctx.diagnostics.hasError,
                    "Expected nested class calls to resolve through the enclosing object, got: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test func regularNestedClassDoesNotCaptureEnclosingInstance() throws {
        try withSemaContext("""
        class RegularOwner {
            fun answer(): Int = 2
            class Nested {
                fun implicitAnswer(): Int = answer()
                fun qualifiedAnswer(owner: RegularOwner): Int = owner.answer()
            }
        }
        """) { ctx in
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "Expected only the implicit instance-member call to fail, got: \(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0002",
                    "Expected the non-inner nested class to keep rejecting an implicit outer instance call, got: \(errors)")
        }
    }

    private func withSemaContext(
        _ source: String,
        body: (CompilationContext) throws -> Void
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            try body(ctx)
        }
    }
}
#endif
