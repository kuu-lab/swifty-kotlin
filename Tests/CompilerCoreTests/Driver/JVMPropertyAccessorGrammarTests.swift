#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

/// JVM source grammar coverage for property accessors, including the
/// explicit getter return type (`val x get(): Int = 1`) that kotlinc accepts
/// and uses for property type inference.
@Suite struct JVMPropertyAccessorGrammarTests {
    @Test(arguments: [
        "val x get(): Int = 1",
        "val x get(): Int { return 1 }",
        "class A { val x get(): Int = 1 }",
        "class A { val x get(): Int { return 1 } }",
        "class A { val x: Int get(): Int = 1 }",
        "class A { var x: Int get(): Int = 1 set(value) { field = value } }",
        "val s get(): String? = null",
        "val f get(): () -> Unit = {}",
        "val g get(): List<Int> = emptyList()",
        "class A { val x get(): @Suppress(\"UNCHECKED_CAST\") Int = 1 }",
    ])
    func acceptsGetterReturnTypes(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        // A getter return type requires a parameter list and a type.
        "val x get(): = 1",
        "val x get() :",
        // Setter parameter types stay inside the parameter list; a colon
        // after `set(value)` is not a return type.
        "var x: Int get() = 1 set(value): Unit { field = value }",
    ])
    func rejectsMalformedAccessorReturnTypes(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(context.diagnostics.hasError)
    }

    @Test(arguments: [
        // Getters cannot declare parameters; only setters take the value.
        "val x get(unused: Int): Int = 1",
        "class A { val x get(unused: Int) { return 1 } }",
        "class A { val x get(unused: Int): Int { return 1 } }",
    ])
    func rejectsGetterParameters(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try ParsePhase().run(context)
        try JVMSourceValidationPhase().run(context)
        try BuildASTPhase().run(context)
        #expect(context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "val x get() = 1",
        "class A { val x: Int get() = 1 }",
        "class A { var x: Int = 0 get() = field set(value) { field = value } }",
    ])
    func acceptsParameterlessAccessors(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try ParsePhase().run(context)
        try JVMSourceValidationPhase().run(context)
        try BuildASTPhase().run(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }
}
#endif
