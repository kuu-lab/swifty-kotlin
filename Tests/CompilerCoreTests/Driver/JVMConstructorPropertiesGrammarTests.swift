#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite struct JVMConstructorPropertiesGrammarTests {
    @Test(arguments: [
        "class Validator(private vararg val values: Int)",
        "class Validator(private val prefix: String, private vararg val values: Int)",
        "class Validator(vararg private val values: Int)",
        "class Validator(internal vararg var values: Int)",
        "annotation class A\nclass Validator(@A private vararg val values: Int)",
        "annotation class A\nclass Validator(@A vararg private val values: Int)",
    ])
    func acceptsPrimaryConstructorPropertyModifierOrders(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "class Validator(private vararg val)",
        "class Validator(private val vararg values: Int)",
        "class Validator(vararg val values)",
        "class Validator(vararg)",
    ])
    func rejectsMalformedPrimaryConstructorPropertyPrefixes(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(context.diagnostics.hasError)
    }

    @Test(arguments: [
        "annotation class A\nclass Validator(private vararg @A val values: Int)",
        "annotation class A\nclass Validator(private @A vararg val values: Int)",
        "annotation class A\nclass Validator(vararg @A private val values: Int)",
    ])
    func rejectsPrimaryConstructorPropertyAnnotationsAfterModifiers(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(context.diagnostics.hasError)
    }
}
#endif
