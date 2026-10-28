#if canImport(Testing)
import Testing
@testable import CompilerCore
@testable import CompilerTestSupport

@Suite struct PrivateInterfaceMethodOverrideTests {
    @Test func privateInterfaceMethodIsNotInheritedBySameNamedClassMethod() throws {
        let privateInterfaceSource = """
        interface A {
            private fun foo(): Int = 1
            fun bar(): Int = foo()
        }

        class B : A {
            private fun foo(): Int = 2
        }
        """
        try withTemporaryFile(contents: privateInterfaceSource) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: context)
            #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        }
    }

    @Test func publicInterfaceMethodStillRequiresOverride() throws {
        let publicInterfaceSource = """
        interface A {
            fun foo(): Int
        }

        class B : A {
            fun foo(): Int = 2
        }
        """
        try withTemporaryFile(contents: publicInterfaceSource) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: context)
        }
    }
}
#endif
