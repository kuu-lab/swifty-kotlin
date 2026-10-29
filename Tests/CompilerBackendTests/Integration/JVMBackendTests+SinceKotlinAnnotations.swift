#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    // KUU-3187: kotlin.SinceKotlin / kotlin.DeprecatedSinceKotlin are real
    // stdlib annotation classes. They must emit like kotlinc (BINARY retention
    // lands in RuntimeInvisibleAnnotations) instead of aborting with
    // KSWIFTK-JVM-0001 "Unsupported JVM annotation".
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func sinceKotlinAnnotationsEmitLikeKotlinStdlib(mode: EmitMode) throws {
        let source = """
        @SinceKotlin("1.5")
        @DeprecatedSinceKotlin(warningSince = "1.6", errorSince = "1.8")
        fun main() { println("ok") }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let app = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let inspection = try javap(["-v", "-p", "-classpath", app.path, "HelloKt"])
            #expect(inspection.exitCode == 0, "\(inspection.stderr)")
            let invisible = inspection.stdout.components(separatedBy: "RuntimeInvisibleAnnotations:")
            #expect(invisible.count > 1, "\(inspection.stdout)")
            #expect(invisible[1].contains("kotlin.SinceKotlin("), "\(inspection.stdout)")
            #expect(invisible[1].contains("version=\"1.5\""), "\(inspection.stdout)")
            // DeprecatedSinceKotlin keeps RUNTIME retention, like kotlin-stdlib.
            let visible = inspection.stdout.components(separatedBy: "RuntimeVisibleAnnotations:")
            #expect(visible.count > 1, "\(inspection.stdout)")
            #expect(visible.contains { $0.contains("kotlin.DeprecatedSinceKotlin(") && $0.contains("warningSince=\"1.6\"") && $0.contains("errorSince=\"1.8\"") }, "\(inspection.stdout)")
        }
    }

    // WasExperimental is internal in kotlin-stdlib, so user code must reject it
    // (kotlinc reports "it is internal in file"), not silently drop it.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func wasExperimentalRejectsUserUsageLikeKotlinc(mode: EmitMode) throws {
        let source = """
        annotation class Marker
        @WasExperimental(markerClass = [Marker::class])
        fun main() { println("ok") }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 1)
            #expect(result.1.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-0044" && $0.message.contains("internal") }, "\(result.1.map(\.message))")
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path))
        }
    }

    // The bundled kotlin-stdlib annotation classes are declared for consumers
    // through the JVM catalog, so @SinceKotlin works without a --classpath jar.
    @Test
    func sinceKotlinDeclarationsAreInjectedForConsumers() throws {
        let manifest = try JVMStdlibCatalog.manifest()
        let paths = manifest.declarations.map(\.path)
        #expect(paths.contains("kotlin/SinceKotlin.kt"))
        #expect(paths.contains("kotlin/DeprecatedSinceKotlin.kt"))
        #expect(paths.contains("kotlin/WasExperimental.kt"))
        for path in ["kotlin/SinceKotlin.kt", "kotlin/DeprecatedSinceKotlin.kt", "kotlin/WasExperimental.kt"] {
            let data = try JVMStdlibCatalog.read(path)
            #expect(String(decoding: data, as: UTF8.self).hasPrefix("package kotlin"))
        }
    }
}
#endif
