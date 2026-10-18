#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

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
        let ctx = makeContextFromSource("""
        class Outer(val value: Int) {
            fun fetch(index: Int): Int = value + index
            inner class Inner {
                fun compute(): Int = fetch(1)
            }
        }
        """)

        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError,
                "Expected unqualified outer member call to resolve, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }
}
#endif
