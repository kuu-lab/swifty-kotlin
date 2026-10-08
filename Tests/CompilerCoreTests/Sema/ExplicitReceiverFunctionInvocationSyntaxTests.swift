@testable import CompilerCore
import Testing

/// KUU-1453: an explicit `recv.name` without parentheses is property-access
/// syntax. Kotlin/JVM rejects it for functions with
/// "function invocation 'name()' expected" — only real properties, property
/// accessors, and the bundled property-facade decls may bind that way.
@Suite
struct ExplicitReceiverFunctionInvocationSyntaxTests {

    private func compileAndCollectDiagnostics(_ source: String) throws -> DiagnosticEngine {
        var result: DiagnosticEngine?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = ctx.diagnostics
        }
        return try requireTestValue(result, "Expected diagnostics after Sema")
    }

    @Test
    func memberFunctionPropertySyntaxIsRejected() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        class C { fun m(): Int = 7 }

        fun main() {
            val c = C()
            println(c.m)
        }
        """)

        let found = diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0309" }
        #expect(found, "Expected SEMA-0309 for member function property syntax, got: \(diagnostics.diagnostics.map(\.code))")
    }

    @Test
    func userExtensionFunctionPropertySyntaxIsRejected() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun <T> List<T>.myProp(): Int = 99

        fun main() {
            val l = listOf(1, 2, 3)
            println(l.myProp)
        }
        """)

        let found = diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0309" }
        #expect(found, "Expected SEMA-0309 for extension function property syntax, got: \(diagnostics.diagnostics.map(\.code))")
    }

    @Test
    func bundledExtensionFunctionPropertySyntaxIsRejected() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun main() {
            val l = listOf(1, 2, 3)
            println(l.first)
        }
        """)

        let found = diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0309" }
        #expect(found, "Expected SEMA-0309 for bundled extension function property syntax, got: \(diagnostics.diagnostics.map(\.code))")
    }

    @Test
    func safeCallFunctionPropertySyntaxIsRejected() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        class C { fun m(): Int = 7 }

        fun main() {
            val c: C? = C()
            println(c?.m)
        }
        """)

        let found = diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0309" }
        #expect(found, "Expected SEMA-0309 for safe-call function property syntax, got: \(diagnostics.diagnostics.map(\.code))")
    }

    @Test
    func explicitFunctionInvocationsAreAccepted() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        class C { fun m(): Int = 7 }
        fun <T> List<T>.myProp(): Int = 99

        fun main() {
            val c = C()
            println(c.m())
            val l = listOf(1, 2, 3)
            println(l.myProp())
            println(l.first())
        }
        """)

        let errors = diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors for explicit invocations: \(errors)")
    }

    @Test
    func functionValueInvokePropertySyntaxIsRejected() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun main() {
            val f: Function0<Int> = { 7 }
            println(f.invoke)
        }
        """)

        let found = diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0309" }
        #expect(found, "Expected SEMA-0309 for function-value invoke property syntax, got: \(diagnostics.diagnostics.map(\.code))")
    }

    @Test
    func bundledPropertyFacadesAreAccepted() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun main() {
            val l = listOf(1, 2, 3)
            println(l.lastIndex)
            println(l.indices)
            val s = "abc"
            println(s.lastIndex)
            println(s.indices)
        }
        """)

        let errors = diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors for bundled property facades: \(errors)")
    }

    @Test
    func syntheticCharPropertyFacadesAreAccepted() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun main() {
            val ch = 'a'
            println(ch.code)
            println(ch.category)
            println(ch.directionality)
        }
        """)

        let errors = diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors for Char property facades: \(errors)")
    }

    @Test
    func declaredPropertiesAreAccepted() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        class C { val p: Int = 3 }
        val List<Int>.elems: Int get() = 5

        fun main() {
            val c = C()
            println(c.p)
            val l = listOf(1, 2, 3)
            println(l.elems)
        }
        """)

        let errors = diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors for declared properties: \(errors)")
    }
}
