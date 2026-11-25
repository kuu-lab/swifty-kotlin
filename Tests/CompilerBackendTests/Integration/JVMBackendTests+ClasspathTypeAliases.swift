#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    private func coilBitmapTypeAliasFixture(_ root: URL) throws -> (library: URL, classes: URL) {
        let fixture = root.appendingPathComponent("fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        try """
        package fixture;
        public class Target {
            public String label() { return "bitmap"; }
        }
        """.write(to: fixture.appendingPathComponent("Target.java"), atomically: true, encoding: .utf8)
        let classes = root.appendingPathComponent("target-classes")
        _ = try jvmTool("javac", ["-d", classes.path, "fixture/Target.java"], root: root)
        try """
        package coil3

        typealias Bitmap = fixture.Target
        private typealias HiddenBitmap = fixture.Target
        internal typealias InternalBitmap = fixture.Target

        fun bitmapLabel(bitmap: Bitmap): String = bitmap.label()
        """.write(to: root.appendingPathComponent("Bitmap.kt"), atomically: true, encoding: .utf8)
        try """
        package coil3

        typealias CollisionKt = fixture.Target

        fun collisionValue(): Int = 3
        """.write(to: root.appendingPathComponent("Collision.kt"), atomically: true, encoding: .utf8)
        try """
        package coil3

        open class ProtectedBase {
            protected typealias Alias = fixture.Target
        }
        """.write(to: root.appendingPathComponent("Protected.kt"), atomically: true, encoding: .utf8)
        _ = try jvmTool("kotlinc", ["Bitmap.kt", "Collision.kt", "Protected.kt", "-cp", classes.path, "-d", "coil-bitmap.jar"], root: root)
        return (root.appendingPathComponent("coil-bitmap.jar"), classes)
    }

    @Test
    func importedKotlinMetadataTypeAliasResolvesAndMissingAliasStillFails() throws {
        try withWorkspace { root in
            let fixture = try coilBitmapTypeAliasFixture(root)
            let classpath = [fixture.library.path, fixture.classes.path]
            let index = try JVMClasspathIndex.load(classpath)
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "ClasspathTypeAliasProbe",
                    inputs: [root.appendingPathComponent("consumer.kt").path],
                    outputPath: root.appendingPathComponent("out").path,
                    emit: .jvmJar,
                    target: .hostDefault(),
                    includeStdlib: false,
                    allowDefaultStdlibLibrary: false
                ),
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try index.inject(into: ctx)
            let facadePath = "<kswiftk-jvm-import>/coil3/BitmapKt.kt"
            let facadeID = try #require(ctx.sourceManager.fileID(forPath: facadePath), "missing facade stub")
            let facade = String(decoding: ctx.sourceManager.contents(of: facadeID), as: UTF8.self)
            #expect(facade.contains("typealias `Bitmap`"), "\(facade)")
            let source = """
            import coil3.Bitmap

            fun describe(bitmap: Bitmap?): String = if (bitmap == null) "null" else "bitmap"
            fun main() { println(describe(null)) }
            """
            let result = try compile(source, root: root, mode: .jvmJar, classpath: classpath)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java([
                "-cp", ([root.appendingPathComponent("hello.jar").path] + classpath + [m11Runtime()]).joined(separator: ":"),
                "HelloKt",
            ])
            #expect(execution.stdout == "null\n")
            #expect(execution.stderr.isEmpty)

            let collision = try compile("""
            import coil3.CollisionKt
            import coil3.collisionValue

            fun collisionIsNull(value: CollisionKt?): Boolean = value == null
            fun main() { println(collisionIsNull(null)); println(collisionValue()) }
            """, root: root, mode: .jvmJar, classpath: classpath)
            try #require(collision.0 == 0, "\(collision.1.map(\.message))")

            let protectedAlias = try compile("""
            import coil3.ProtectedBase

            class ConsumerSub : ProtectedBase() {
                fun check(value: ProtectedBase.Alias?): Boolean = value == null
            }
            fun main() { println(ConsumerSub().check(null)) }
            """, root: root, mode: .jvmJar, classpath: classpath)
            try #require(protectedAlias.0 == 0, "\(protectedAlias.1.map(\.message))")

            let missing = try compile("""
            import coil3.Missing
            fun main() {}
            """, root: root, mode: .jvmJar, classpath: classpath)
            #expect(missing.0 != 0)
            #expect(missing.1.contains { $0.code == "KSWIFTK-SEMA-UNRESOLVED-IMPORT" })

            for alias in ["HiddenBitmap", "InternalBitmap"] {
                let hidden = try compile("""
                import coil3.\(alias)

                fun hiddenIsNull(value: \(alias)?): Boolean = value == null
                """, root: root, mode: .jvmJar, classpath: classpath)
                #expect(hidden.0 != 0)
                #expect(hidden.1.contains { $0.code == "KSWIFTK-SEMA-UNRESOLVED-IMPORT" })
            }
        }
    }
}
#endif
