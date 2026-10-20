#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

struct JVMStdlibCatalogTests {
    @Test
    func declarationsArePackagedSeparatelyFromCompiledBodies() throws {
        let manifest = try JVMStdlibCatalog.manifest()
        #expect(manifest.commonSources.contains("kotlin/Function.kt"))
        #expect(manifest.commonSources.contains("kotlin/Unit.kt"))
        for declaration in manifest.declarations {
            let data = try JVMStdlibCatalog.read(declaration.path)
            #expect(!data.isEmpty)
            #expect(String(decoding: data, as: UTF8.self).contains("package "))
        }
        for stdlib in [false, true] {
            let options = CompilerOptions(moduleName: "Catalog", inputs: stdlib ? [] : ["main.kt"], outputPath: "/private/tmp/catalog.jar", emit: .jvmJar, target: .hostDefault(), stdlibOnly: stdlib)
            let context = CompilationContext(options: options, sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner())
            try JVMPreparationPhase().run(context)
            #expect(!context.diagnostics.hasError)
            let paths = context.sourceManager.fileIDs().map { context.sourceManager.path(of: $0) }
            #expect(paths.contains("<kswiftk-jvm>/stdlib-bridges.kt") == stdlib)
            #expect(paths.contains("<kswiftk-jvm>/console.kt") == !stdlib)
            #expect(paths.contains("<kswiftk-jvm>/unit.kt") == !stdlib)
            #expect(paths.contains { $0.hasSuffix("/Stdlib/kotlin/Unit.kt") } == stdlib)
        }
    }
}
#endif
