@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct ObjectMemberImportTests {
    private let owner = """
    package sample
    object Owner { fun compare(a: Any?, b: Any?): Boolean = a === b }
    """

    @Test(arguments: [
        ("import sample.Owner.compare as compareValues", "compareValues"),
        ("import sample.Owner.compare", "compare"),
        ("import sample.Owner", "Owner.compare"),
    ])
    func explicitObjectMemberCallsResolve(importAndName: (String, String)) throws {
        let usage = """
        \(importAndName.0)
        fun same(a: Any?, b: Any?): Boolean = \(importAndName.1)(a, b)
        fun main() {}
        """
        try withTemporaryFiles(contents: [owner, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func privateObjectMembersRemainInaccessible(aliased: Bool) throws {
        let declaration = owner.replacingOccurrences(of: "fun compare", with: "private fun compare")
        let usage = """
        import sample.Owner.compare\(aliased ? " as compareValues" : "")
        fun same(a: Any?, b: Any?): Boolean = \(aliased ? "compareValues" : "compare")(a, b)
        """
        try withTemporaryFiles(contents: [declaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0040", in: diagnosticsForPath(paths[1], in: ctx))
        }
    }

    @Test
    func objectWildcardImportRemainsRejected() throws {
        let usage = """
        import sample.Owner.*
        fun same(a: Any?, b: Any?): Boolean = compare(a, b)
        """
        try withTemporaryFiles(contents: [owner, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0027", in: diagnosticsForPath(paths[1], in: ctx))
        }
    }

    @Test
    func importedMemberExtensionStillRequiresExtensionReceiver() throws {
        let declaration = """
        package sample
        object Owner { fun Owner.value(): Int = 42 }
        """
        let usage = """
        import sample.Owner.value as importedValue
        fun read(): Int = importedValue()
        """
        try withTemporaryFiles(contents: [declaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0002", in: diagnosticsForPath(paths[1], in: ctx))
        }
    }
}
