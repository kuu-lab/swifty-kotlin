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
    func toStringFunctionPropertySyntaxIsRejected() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        class C { override fun toString(): String = "C" }
        class PropertyHolder { val toString: String = "property" }

        fun main() {
            val number = 1.toString
            val c = C()
            val member = c.toString
            val any: Any = c
            val anyToString = any.toString
            val nullable: Any? = c
            val safeToString = nullable?.toString
            val propertyToString = PropertyHolder().toString
            println(1.toString())
            println(c.toString())
        }
        """)

        let invocationErrors = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0309" }
        #expect(
            invocationErrors.count == 4,
            "Expected SEMA-0309 for each bare toString member access, got: \(diagnostics.diagnostics.map(\.code))"
        )
        #expect(
            diagnostics.diagnostics.filter { $0.severity == .error }.count == 4,
            "Explicit toString() calls should remain valid, got: \(diagnostics.diagnostics)"
        )
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

    @Test(arguments: ["code", "category", "directionality"])
    func syntheticCharPropertyInvocationsAreRejected(name: String) throws {
        for access in ["'a'.\(name)()", "value?.\(name)()"] {
            let diagnostics = try compileAndCollectDiagnostics("""
            fun main() {
                val value: Char? = 'a'
                println(\(access))
            }
            """)
            #expect(diagnostics.hasError, "\(access) must not invoke a synthetic property facade")
        }
    }

    @Test
    func sameNamedCharExtensionFunctionsRemainCallable() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun Char.code(): Int = this.code + 10
        fun Char.category(): Int = 20
        fun Char.directionality(): Int = 30
        fun main() {
            val value: Char? = 'a'
            println('a'.code()); println(value?.code())
            println('a'.category()); println('a'.directionality())
            println('a'.code); println('a'.category); println('a'.directionality)
        }
        """)
        #expect(!diagnostics.hasError, "Unexpected errors: \(diagnostics.diagnostics)")
    }

    @Test
    func charCodeValuesUseThePropertyInvokeBridge() throws {
        try withTemporaryFile(contents: """
        operator fun Int.invoke(delta: Int): Int = this + delta
        fun read(): Int = 'a'.code(20)
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "read", in: module, interner: ctx.interner)
            let calls = body.compactMap { instruction -> String? in
                if case let .call(_, callee, _, _, _, _, _, _) = instruction { return ctx.interner.resolve(callee) }
                return nil
            }
            #expect(calls.filter { $0 == "kk_char_code" }.count == 1)
            #expect(calls.filter { $0 == "invoke" }.count == 1)
        }
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
