@testable import CompilerCore
import Testing

@Suite
struct ClassDeprecationTests {
    @Test
    func deprecatedClassIsReportedAtConstructorCalls() throws {
        let source = """
        @Deprecated("gone", level = DeprecationLevel.ERROR)
        class Old(val x: Int)

        @Deprecated("gone", level = DeprecationLevel.HIDDEN)
        class Hidden(val y: Int)

        fun main() {
            println(Old(1).x)
            println(Hidden(2).y)
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let deprecated = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-DEPRECATED"
            }
            #expect(deprecated.count == 2, "Expected both constructor calls to be deprecated, got: \(deprecated)")
            #expect(deprecated.allSatisfy { $0.severity == .error })
            #expect(deprecated.allSatisfy { $0.message.contains("gone") })
        }
    }

    @Test
    func bundledLegacyAtomicConstructorIsDeprecated() throws {
        let source = """
        fun main() {
            kotlin.native.concurrent.AtomicReference("hi")
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let deprecated = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-DEPRECATED"
            }
            #expect(deprecated.count == 1, "Expected the bundled legacy atomic constructor to be deprecated, got: \(deprecated)")
            #expect(deprecated.first?.severity == .error)
            #expect(deprecated.first?.message.contains("Use kotlin.concurrent.atomics.AtomicReference instead.") == true)
        }
    }

    @Test
    func deprecatedClassIsReportedInTypeReferencesAndSupertypes() throws {
        let source = """
        @Deprecated("error class", level = DeprecationLevel.ERROR)
        open class Old

        @Deprecated("hidden class", level = DeprecationLevel.HIDDEN)
        open class Hidden

        fun acceptsBoth(old: Old, hidden: Hidden) {
            val local: Old? = null
        }

        class OldChild : Old()
        class HiddenChild : Hidden()
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let deprecated = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-DEPRECATED"
            }
            #expect(deprecated.count == 5, "Expected diagnostics for three type references and two supertypes, got: \(deprecated)")
            #expect(deprecated.allSatisfy { $0.severity == .error })
            #expect(deprecated.contains { $0.message.contains("error class") })
            #expect(deprecated.contains { $0.message.contains("hidden class") })
        }
    }
}
