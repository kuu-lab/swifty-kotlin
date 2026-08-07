@testable import CompilerCore
import Foundation
import Testing

/// BUG-159: top-level signatures must resolve types declared in files that are
/// processed later, independently of the order in which inputs are given.
@Suite
struct CrossFileForwardReferenceSemaTests {
    private func semaContext(sources: [String]) throws -> CompilationContext {
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)
        return ctx
    }

    @Test func topLevelFunctionSignatureResolvesTypeDeclaredInLaterFile() throws {
        let user = """
        fun useB(x: B?): Int = 0
        fun makeB(): B = B()
        fun B.ext(): Int = 0
        val prop: B? = null
        """
        let later = """
        class B
        """
        for sources in [[user, later], [later, user]] {
            let ctx = try semaContext(sources: sources)
            assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
        }
    }

    @Test func classMemberSignatureResolvesTypeDeclaredInLaterFile() throws {
        let user = """
        class A {
            fun make(): Later = Later()
            val value: Later? = null
        }
        """
        let later = """
        class Later
        """
        let ctx = try semaContext(sources: [user, later])
        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    @Test func typeAliasResolvesTypeDeclaredInLaterFile() throws {
        let user = """
        typealias Alias = Later
        fun useAlias(x: Alias?): Int = 0
        """
        let later = """
        interface Later
        """
        let ctx = try semaContext(sources: [user, later])
        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    @Test func duplicateTopLevelClassAcrossFilesIsStillReported() throws {
        let ctx = try semaContext(sources: ["class Dup", "class Dup"])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-SEMA") })
    }
}
