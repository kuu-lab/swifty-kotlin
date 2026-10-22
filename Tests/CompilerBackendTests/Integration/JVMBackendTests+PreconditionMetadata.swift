#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func ownStdlibCheckAndErrorExportNormalReturnContractsToOfficialConsumers() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            fun checked(value: String?): Int { check(value != null); return value.length }
            fun typed(value: Any?): Int { check(value is String) { "type" }; return value.length }
            fun main() { println(checked("abc")); println(typed("text")) }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            let accepted = try jvmTool("kotlinc", ["consumer.kt", "-no-stdlib", "-no-reflect", "-classpath", library.path, "-d", "consumer.jar"], root: root)
            try #require(accepted.exitCode == 0, "\(accepted.stderr)")
            let execution = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + library.path, "ConsumerKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "3\n4\n")
            #expect(execution.stderr.isEmpty)
            try """
            fun unchecked(value: String?): Int { check(value == null); return value.length }
            """.write(to: root.appendingPathComponent("rejected.kt"), atomically: true, encoding: .utf8)
            do {
                _ = try jvmTool("kotlinc", ["rejected.kt", "-no-stdlib", "-no-reflect", "-classpath", library.path, "-d", "rejected.jar"], root: root)
                Issue.record("Kotlin consumer unexpectedly accepted the nullable receiver.")
            } catch let CommandRunnerError.nonZeroExit(rejected) {
                #expect(rejected.exitCode != 0)
                #expect(rejected.stderr.contains("nullable receiver"))
            }
        }
    }

    @Test
    func ownStdlibCheckAndErrorMetadataRecordsBooleanNormalReturnImplications() throws {
        let library = try ownStdlibLibrary()
        let runtime = try m11Runtime()
        let official = runtime.components(separatedBy: ":")
        let compiler = URL(fileURLWithPath: official[0]).deletingLastPathComponent().appendingPathComponent("kotlin-compiler.jar")
        try #require(FileManager.default.fileExists(atPath: compiler.path))
        try withWorkspace { root in
            // Decode with Kotlin's protobuf implementation rather than checking
            // the writer's own intermediate contract field.
            try #"""
            import java.net.URL;
            import java.net.URLClassLoader;
            import java.lang.annotation.Annotation;
            import java.util.ArrayList;
            import java.util.Collections;
            import kotlin.Pair;
            import org.jetbrains.kotlin.metadata.ProtoBuf;
            import org.jetbrains.kotlin.metadata.jvm.deserialization.JvmNameResolver;
            import org.jetbrains.kotlin.metadata.jvm.deserialization.JvmProtoBufUtil;
            public class ContractConsumer {
                public static void main(String[] args) throws Exception {
                    URL[] paths = {new java.io.File(args[0]).toURI().toURL(), new java.io.File(args[1]).toURI().toURL()};
                    try (URLClassLoader loader = new URLClassLoader(paths, ClassLoader.getPlatformClassLoader())) {
                        Class<?> owner = loader.loadClass("kotlin.PreconditionsKt");
                        Annotation metadata = null;
                        for (Annotation value : owner.getDeclaredAnnotations()) {
                            if (value.annotationType().getName().equals("kotlin.Metadata")) metadata = value;
                        }
                        if (metadata == null) throw new AssertionError("Missing Kotlin metadata");
                        String[] d1 = (String[])metadata.annotationType().getMethod("d1").invoke(metadata);
                        String[] d2 = (String[])metadata.annotationType().getMethod("d2").invoke(metadata);
                        Pair<JvmNameResolver, ProtoBuf.Package> data = JvmProtoBufUtil.readPackageDataFrom(d1, d2);
                        ArrayList<String> rows = new ArrayList<>();
                        for (ProtoBuf.Function function : data.getSecond().getFunctionList()) {
                            if (!data.getFirst().getString(function.getName()).equals("check")) continue;
                            if (!function.hasContract() || function.getContract().getEffectCount() != 1) throw new AssertionError("Missing single contract");
                            ProtoBuf.Effect effect = function.getContract().getEffect(0);
                            if (!effect.hasConclusionOfConditionalEffect()) throw new AssertionError("Missing implication");
                            ProtoBuf.Expression condition = effect.getConclusionOfConditionalEffect();
                            rows.add(function.getValueParameterCount() + ":" + effect.getEffectType() + ":" + effect.getEffectConstructorArgumentCount() + ":" + condition.getValueParameterReference() + ":" + condition.getFlags() + ":" + condition.hasConstantValue());
                        }
                        Collections.sort(rows);
                        for (String row : rows) System.out.println(row);
                    }
                }
            }
            """#.write(to: root.appendingPathComponent("ContractConsumer.java"), atomically: true, encoding: .utf8)
            let classpath = compiler.path + ":" + runtime
            let compiled = try jvmTool("javac", ["-classpath", classpath, "ContractConsumer.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let execution = try java(["-cp", root.path + ":" + classpath, "ContractConsumer", library.path, official[0]])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "1:RETURNS_CONSTANT:0:1:0:false\n2:RETURNS_CONSTANT:0:1:0:false\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
