#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func reifiedEnumValuesExecuteAndExposeJavaArrays() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = try String(
                contentsOf: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Scripts/diff_cases/enum_values_reified_jvm.kt"),
                encoding: .utf8
            )
            let app = try m22Build(
                root: root,
                sources: [("EnumProbe.kt", source)],
                name: "app.jar",
                classpath: [library.path]
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let execution = try java(["-cp", app.0.path + ":" + library.path, "EnumProbeKt"])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "2\nRED\nBLUE\n3\nFIRST\nSECOND\nTHIRD\n0\n0\n")
            #expect(execution.stderr.isEmpty)

            let javaConsumer = root.appendingPathComponent("EnumValuesConsumer.java")
            let consumerClasses = root.appendingPathComponent("consumer")
            try FileManager.default.createDirectory(at: consumerClasses, withIntermediateDirectories: true)
            try """
            import java.util.Arrays;

            public class EnumValuesConsumer {
                public static void main(String[] args) {
                    Color[] colors = EnumProbeKt.colorValues();
                    if (!Arrays.equals(colors, new Color[] {Color.RED, Color.BLUE})) throw new AssertionError(Arrays.toString(colors));
                    if (colors == EnumProbeKt.colorValues()) throw new AssertionError("enumValues must return a fresh array");
                    colors[0] = null;
                    if (EnumProbeKt.colorValues()[0] != Color.RED) throw new AssertionError("array mutation escaped");

                    Larger[] larger = EnumProbeKt.largerValues();
                    if (!Arrays.equals(larger, new Larger[] {Larger.FIRST, Larger.SECOND, Larger.THIRD})) throw new AssertionError(Arrays.toString(larger));
                    if (EnumProbeKt.emptyValues().length != 0 || EnumProbeKt.emptyCount() != 0) throw new AssertionError("empty enum");
                    if (EnumProbeKt.colorCount() != 2 || EnumProbeKt.largerCount() != 3) throw new AssertionError("enum count");
                    System.out.println("JAVA_CONSUMER_OK");
                }
            }
            """.write(to: javaConsumer, atomically: true, encoding: .utf8)
            let compilation = try javac([
                "-cp", app.0.path + ":" + library.path,
                "-d", consumerClasses.path,
                javaConsumer.path,
            ])
            #expect(compilation.exitCode == 0, "\(compilation.stderr)")
            let javaExecution = try java([
                "-cp", consumerClasses.path + ":" + app.0.path + ":" + library.path,
                "EnumValuesConsumer",
            ])
            #expect(javaExecution.exitCode == 0, "\(javaExecution.stderr)")
            #expect(javaExecution.stdout == "JAVA_CONSUMER_OK\n")
            #expect(javaExecution.stderr.isEmpty)
        }
    }

    @Test(arguments: [
        "fun <T : Enum<T>> bad() = enumValues<T>()",
        "inline fun <reified T> bad() = enumValues<T>()",
        "inline fun <reified T : Enum<T>> bad() = enumValues<T?>()",
        "fun bad() = enumValues<String>()",
    ])
    func reifiedEnumValuesRejectInvalidTypeArguments(source: String) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar, classpath: [library.path])
            #expect(result.0 == 1)
            #expect(result.1.contains {
                $0.code == "KSWIFTK-SEMA-0002" && $0.message.contains("non-nullable enum")
            })
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
        }
    }
}
#endif
