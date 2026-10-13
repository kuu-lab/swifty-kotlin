@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SerializationKindSemaTests {
    private func analyze(_ source: String) -> CompilationContext {
        let input = "/tmp/serialization-kind-\(UUID().uuidString).kt"
        let options = CompilerOptions(moduleName: "Kinds", inputs: [input], outputPath: "/tmp/kinds",
                                      emit: .executable, target: defaultTargetTriple(), allowDefaultStdlibLibrary: false)
        return CompilerDriver().runFrontend(options: options, inMemorySources: [input: Data(source.utf8)]).context
    }

    @Test(arguments: [false, true])
    func polymorphicKindRetainsTheWarningOptInContract(optedIn: Bool) {
        let context = analyze("""
        import kotlinx.serialization.ExperimentalSerializationApi
        import kotlinx.serialization.descriptors.PolymorphicKind
        \(optedIn ? "@OptIn(ExperimentalSerializationApi::class)" : "")
        fun kind(): PolymorphicKind = PolymorphicKind.OPEN
        """)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let warnings = context.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.message.contains("ExperimentalSerializationApi")
        }
        #expect(warnings.isEmpty == optedIn)
        #expect(warnings.allSatisfy { $0.severity == .warning })
    }

    @Test
    func internalMarkerRequiresErrorLevelOptIn() {
        let context = analyze("""
        import kotlinx.serialization.InternalSerializationApi
        @InternalSerializationApi fun internalApi() {}
        fun caller() { internalApi() }
        """)
        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error && $0.message.contains("InternalSerializationApi")
        })
    }

    @Test
    func sealedApiMarkerCannotBeUsedAsADirectAnnotation() {
        let context = analyze("""
        import kotlinx.serialization.SealedSerializationApi
        @SealedSerializationApi class Bad
        """)
        #expect(context.diagnostics.diagnostics.contains { $0.message.contains("not applicable") })
    }

    @Test(arguments: [false, true])
    func sealedApiMarkerRetainsSubclassOptInMessage(optedIn: Bool) {
        let context = analyze("""
        import kotlinx.serialization.SealedSerializationApi
        @SubclassOptInRequired(SealedSerializationApi::class) open class Contract
        \(optedIn ? "@OptIn(SealedSerializationApi::class)" : "")
        class Child: Contract()
        """)
        let diagnostics = context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-SUBCLASS-OPT-IN" }
        #expect(diagnostics.isEmpty == optedIn)
        let expectedMessage = "This class or interface should not be inherited/implemented outside of kotlinx.serialization library. " +
            "Note it is still permitted to use it directly. Read its documentation about inheritance for details."
        #expect(diagnostics.allSatisfy { $0.severity == .error && $0.message.hasSuffix(expectedMessage) })
        #expect(!optedIn || !context.diagnostics.hasError)
    }

    @Test
    func sealedKindCannotBeSubclassedInAnotherPackage() {
        let context = analyze("""
        package external
        import kotlinx.serialization.descriptors.SerialKind
        class Bad: SerialKind()
        """)
        #expect(context.diagnostics.diagnostics.contains { $0.message.contains("sealed subclasses must be in the same module") })
    }

    @Test(arguments: [false, true])
    func sourceInjectionRetainsTheStdlibModuleBoundary(nested: Bool) {
        let context = analyze("""
        package kotlinx.serialization.descriptors
        \(nested ? "class Holder { class Bad: SerialKind() }" : "class Bad: SerialKind()")
        """)
        #expect(context.diagnostics.diagnostics.contains { $0.message.contains("sealed subclasses must be in the same module") })
    }

    @Test
    func sealedKindCannotBeConstructed() {
        let context = analyze("""
        import kotlinx.serialization.descriptors.SerialKind
        fun bad() = SerialKind()
        """)
        #expect(context.diagnostics.hasError)
        #expect(context.diagnostics.diagnostics.contains { $0.message.contains("abstract") || $0.message.contains("sealed") })
    }
}
