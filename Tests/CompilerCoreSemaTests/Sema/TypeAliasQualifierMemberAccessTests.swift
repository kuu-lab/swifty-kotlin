@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct TypeAliasQualifierMemberAccessTests {
    private func context(_ sources: [String], includeStdlib: Bool = false) throws -> CompilationContext {
        let paths = sources.indices.map { "/typealias-qualifier/input\($0).kt" }
        let ctx = makeCompilationContext(inputs: paths, includeStdlib: includeStdlib)
        for (path, source) in zip(paths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        try runSema(ctx)
        return ctx
    }

    @Test func nestedClassConstructorThroughAliasIsRejected() throws {
        let ctx = try context(["""
        class Outer2 { class Nested }
        typealias A2 = Outer2
        fun main() { A2.Nested() }
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
    }

    @Test func bareNestedClassReferenceThroughAliasIsRejected() throws {
        let ctx = try context(["""
        class Outer2 { class Nested }
        typealias A2 = Outer2
        fun main() { val x = A2.Nested }
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
    }

    @Test func innerClassConstructorThroughAliasIsRejected() throws {
        let ctx = try context(["""
        class Outer { inner class I }
        typealias A = Outer
        fun main() { A.I() }
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
    }

    @Test func nestedObjectThroughAliasIsRejected() throws {
        let ctx = try context(["""
        class Outer2 { object Inner }
        typealias A2 = Outer2
        fun main() { A2.Inner }
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
    }

    @Test func companionObjectThroughAliasIsRejected() throws {
        let ctx = try context(["""
        class Outer2 { companion object { const val X = 1 } }
        typealias A2 = Outer2
        fun main() { val a = A2.Companion; val b = A2.Companion.X }
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
    }

    @Test func namedCompanionThroughAliasIsRejected() throws {
        let ctx = try context(["""
        class Outer3 { companion object Named { fun go() = 1 } }
        typealias A3 = Outer3
        fun main() { A3.Named.go() }
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
    }

    @Test func chainedAliasQualifierIsRejected() throws {
        let ctx = try context(["""
        class Outer2 { class Nested }
        typealias A2 = Outer2
        typealias B = A2
        fun main() { B.Nested() }
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
    }

    @Test func aliasQualifiedTypeReferenceIsRejected() throws {
        let ctx = try context(["""
        class Outer2 { class Nested }
        typealias A2 = Outer2
        fun main() { val x: A2.Nested? = null }
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0025" })
    }

    @Test func aliasQualifiedIsCheckIsRejected() throws {
        let ctx = try context(["""
        class Outer2 { class Nested }
        typealias A2 = Outer2
        fun main() { val x: Any = Outer2.Nested(); val b = x is A2.Nested }
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0025" })
    }

    @Test func companionFunctionThroughAliasResolves() throws {
        let ctx = try context(["""
        class Outer2 { companion object { fun make() = 1 } }
        typealias A2 = Outer2
        fun main() { A2.make() }
        """])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func companionPropertyThroughAliasResolves() throws {
        let ctx = try context(["""
        class Outer2 { companion object { const val X = 1 } }
        typealias A2 = Outer2
        fun main() { A2.X }
        """])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func enumEntryThroughAliasResolves() throws {
        let ctx = try context(["""
        enum class E { A, B }
        typealias EA = E
        fun main() { EA.A }
        """])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func directAliasConstructorResolves() throws {
        let ctx = try context(["""
        class Outer2(val x: Int = 1)
        typealias A2 = Outer2
        fun main() { A2() }
        """])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func aliasToNestedClassConstructorResolves() throws {
        let ctx = try context(["""
        class Outer2 { class Nested }
        typealias N = Outer2.Nested
        fun main() { N() }
        """])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func genuineClassNameNestedAccessStillResolves() throws {
        let ctx = try context(["""
        class Outer2 { class Nested; object Inner }
        fun main() { Outer2.Nested(); Outer2.Inner }
        """])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func importAliasQualifierStillResolvesNestedAccess() throws {
        let ctx = try context([
            """
            package other
            class Outer2 { class Nested }
            """,
            """
            import other.Outer2 as A2
            fun main() { A2.Nested() }
            """,
        ])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func instanceMemberThroughAliasStaysRejected() throws {
        let ctx = try context(["""
        class Outer2 { fun foo() = 1 }
        typealias A2 = Outer2
        fun main() { A2.foo() }
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
    }
}
