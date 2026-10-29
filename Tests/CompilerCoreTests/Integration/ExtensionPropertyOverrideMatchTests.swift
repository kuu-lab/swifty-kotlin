#if canImport(Testing)
import Testing
@testable import CompilerCore
@testable import CompilerTestSupport

/// KUU-3684: an extension property can never implement a non-extension
/// interface member, so a same-named interface member must not demand
/// `override` on the extension.
@Suite struct ExtensionPropertyOverrideMatchTests {
    @Test func privateExtensionPropertyIgnoresSameNamedInterfaceMember() throws {
        let source = """
        interface Named {
            val length: Int
        }
        class Box(val size: Int)
        class C : Named {
            private val Box.length: Int
                get() = size
            override val length: Int get() = 2
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: context)
            #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        }
    }

    @Test func nonExtensionPropertyIgnoresSameNamedInterfaceExtensionMember() throws {
        let source = """
        class Box(val size: Int)
        interface Named {
            val Box.length: Int
        }
        class C : Named {
            override val Box.length: Int get() = 2
            val length: Int get() = 1
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: context)
            #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        }
    }

    @Test func extensionPropertyStillRequiresOverrideForInterfaceExtensionMember() throws {
        let source = """
        class Box(val size: Int)
        interface Named {
            val Box.length: Int
        }
        class C : Named {
            val Box.length: Int get() = 2
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: context)
        }
    }
}
#endif
