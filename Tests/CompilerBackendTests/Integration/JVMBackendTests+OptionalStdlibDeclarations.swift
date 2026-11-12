#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [
        ("fun main() = println(\"asKotlinRandom\") // asJavaRandom", false),
        ("import kotlin.random.asKotlinRandom as convert", true),
        ("fun probe() = \"${source.`asKotlinRandom`()}\"", true),
    ])
    func platformRandomContractLoadsOnlyForSourceReferences(source: String, expected: Bool) throws {
        let path = "Probe.kt"
        let options = CompilerOptions(moduleName: "Probe", inputs: [path], outputPath: "probe.jar", emit: .jvmJar, target: .hostDefault())
        let sources = SourceManager()
        _ = sources.addFile(path: path, contents: Data(source.utf8), origin: .user)
        let ctx = CompilationContext(options: options, sourceManager: sources, diagnostics: DiagnosticEngine(), interner: StringInterner())

        try JVMStdlibCatalog.injectDeclarations(into: ctx)

        #expect(sources.containsFile(path: "<kswiftk-jvm>/platform-random.kt") == expected)
    }
}
#endif
