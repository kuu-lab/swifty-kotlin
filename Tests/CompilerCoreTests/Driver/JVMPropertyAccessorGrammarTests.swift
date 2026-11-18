#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite struct JVMPropertyAccessorGrammarTests {
    @Test(arguments: [
        "class WikiSite\nclass ActivityTabViewModel { val wikiSiteForTimeline get(): WikiSite { return WikiSite() } }",
        "val Int.isStarted get(): Boolean { return this > 0 }",
        "val answer get(): Int = 42",
        "var maybe get(): String? { return null } set(value) {}",
    ])
    func acceptsExplicitGetterReturnTypes(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }
}
#endif
