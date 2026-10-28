@testable import CompilerCore
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct ForLoopMemberExtensionResolutionTests {
    private func makeContext(_ source: String) -> CompilationContext {
        TestStdlibCache.shared.prepare()
        return makeContextFromSource(source, allowDefaultStdlibLibrary: true)
    }

    @Test
    func rejectsInaccessibleMemberExtensionConvention() throws {
        let ctx = makeContext("""
        class It {
            operator fun hasNext(): Boolean = false
            operator fun next(): Int = 1
        }
        class C
        class X {
            private operator fun C.iterator(): It = It()
        }
        class Y {
            fun test(x: X) {
                with(x) {
                    for (item in C()) {}
                }
            }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0172" }, "\(errors)")
    }

    @Test
    func rejectsInapplicableMemberExtensionConvention() throws {
        let ctx = makeContext("""
        class It {
            operator fun hasNext(): Boolean = false
            operator fun next(): Int = 1
        }
        class C
        class Other
        class X {
            operator fun Other.iterator(): It = It()
            fun test() {
                for (item in C()) {}
            }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0172", "\(errors)")
    }

    @Test
    func reportsAmbiguousMemberExtensionIteratorCandidates() throws {
        let ctx = makeContext("""
        interface Left
        interface Right
        class C : Left, Right
        class It {
            operator fun hasNext(): Boolean = false
            operator fun next(): Int = 1
        }
        class X {
            operator fun Left.iterator(): It = It()
            operator fun Right.iterator(): It = It()
            fun test() {
                for (item in C()) {}
            }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0003", "\(errors)")
    }
}
