#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: ["annotated_expression_immutable_calls", "deprecatedAnnotationContracts", "deprecatedConstContracts"], [EmitMode.jvmClass, .jvmJar])
    func deprecatedAnnotationsPreserveRuntimeValues(name: String, mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try fixtureOrDiffCaseSource(fixtures, name)
        let expected = try String(contentsOf: fixtures.appendingPathComponent(name + ".out"), encoding: .utf8)
        try withWorkspace { root in
            try runRuntimeParity(source, expected: expected, mode: mode, root: root)
            let app = root.appendingPathComponent(mode == .jvmJar ? "own.jar" : "own-classes")
            let result = try java(["-cp", app.path + ":" + m11Runtime(), "HelloKt"])
            #expect(result.stdout == expected)
            #expect(result.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func deprecatedAnnotationsExposeJavaAndKotlinABI(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("deprecatedAnnotationContracts.kt"), encoding: .utf8)
        try withWorkspace { root in
            let own = try ownStdlibLibrary().path
            let official = try m11Runtime()
            let app = try m22Build(root: root, sources: [("hello.kt", source)], name: "api", mode: mode, classpath: [own])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let inspector = #"""
            import java.lang.annotation.*;
            public class Inspect {
                static void check(boolean value) { if (!value) throw new AssertionError(); }
                public static void main(String[] args) throws Exception {
                    kotlin.Deprecated c = Legacy.class.getAnnotation(kotlin.Deprecated.class);
                    check(c.message().equals("class message"));
                    check(c.replaceWith().expression().equals("Fresh()"));
                    check(java.util.Arrays.equals(c.replaceWith().imports(), new String[] {"sample.Fresh", "sample.Api"}));
                    check(java.util.Set.of(kotlin.Deprecated.class.getAnnotation(Target.class).value()).equals(java.util.Set.of(ElementType.TYPE, ElementType.METHOD, ElementType.ANNOTATION_TYPE, ElementType.CONSTRUCTOR)));
                    check(kotlin.ReplaceWith.class.getAnnotation(Target.class).value().length == 0);
                    check(c.level() == kotlin.DeprecationLevel.WARNING);
                    check(kotlin.Deprecated.class.getAnnotation(Retention.class).value() == RetentionPolicy.RUNTIME);
                    check(kotlin.ReplaceWith.class.getAnnotation(Retention.class).value() == RetentionPolicy.CLASS);
                    check(HelloKt.class.getDeclaredMethod("hidden").isSynthetic());
                    check(HelloKt.class.getDeclaredMethod("hidden").getAnnotation(kotlin.Deprecated.class).level() == kotlin.DeprecationLevel.HIDDEN);
                    check(HiddenCtor.class.getDeclaredConstructor().isSynthetic());
                    check(!HiddenType.class.isSynthetic());
                    check(HiddenType.class.getAnnotation(kotlin.Deprecated.class).level() == kotlin.DeprecationLevel.HIDDEN);
                    check(HiddenAnnotationType.class.isAnnotation() && !HiddenAnnotationType.class.isSynthetic());
                    check(HelloKt.class.getDeclaredMethod("error").getAnnotation(kotlin.Deprecated.class).level() == kotlin.DeprecationLevel.ERROR);
                    check(Properties.class.getDeclaredMethod("getOld").getAnnotation(kotlin.Deprecated.class) == null);
                    check(Properties.class.getDeclaredMethod("getOld$annotations").getAnnotation(kotlin.Deprecated.class).message().equals("property"));
                    check(Properties.class.getDeclaredMethod("getGetter").getAnnotation(kotlin.Deprecated.class).message().equals("getter"));
                    check(Properties.class.getDeclaredMethod("getSetter").getAnnotation(kotlin.Deprecated.class) == null);
                    check(Properties.class.getDeclaredMethod("setSetter", int.class).getAnnotation(kotlin.Deprecated.class).message().equals("setter"));
                    System.out.println("ok");
                }
            }
            """#
            try inspector.write(to: root.appendingPathComponent("Inspect.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", app.0.path + ":" + own, "Inspect.java"], root: root)
            for runtime in [own, official] {
                let result = try java(["-cp", root.path + ":" + app.0.path + ":" + runtime, "Inspect"])
                #expect(result.stdout == "ok\n")
                #expect(result.stderr.isEmpty)
            }
            try "class Use { int use() { return HelloKt.warning() + new Properties().getOld(); } }".write(to: root.appendingPathComponent("Use.java"), atomically: true, encoding: .utf8)
            let warning = try jvmTool("javac", ["-Xlint:deprecation", "-cp", app.0.path + ":" + own, "Use.java"], root: root)
            #expect(warning.stderr.contains("warning()") && warning.stderr.contains("getOld()") && warning.stderr.contains("[deprecation]"))
            try "fun main() { println(warning()) }".write(to: root.appendingPathComponent("KotlinPositive.kt"), atomically: true, encoding: .utf8)
            let positive = try jvmTool("kotlinc", ["KotlinPositive.kt", "-cp", app.0.path + ":" + official, "-d", "kotlin-positive.jar"], root: root)
            #expect(positive.stderr.contains("deprecated") && positive.stderr.contains("warning"))
            for runtime in [own, official] {
                let result = try java(["-cp", root.appendingPathComponent("kotlin-positive.jar").path + ":" + app.0.path + ":" + runtime, "KotlinPositiveKt"])
                #expect(result.stdout == "13\n")
                #expect(result.stderr.isEmpty)
            }
            for (name, call) in [("ErrorUse", "error()"), ("HiddenUse", "hidden()")] {
                try "fun main() { println(\(call)) }".write(to: root.appendingPathComponent(name + ".kt"), atomically: true, encoding: .utf8)
                do {
                    _ = try jvmTool("kotlinc", [name + ".kt", "-cp", app.0.path + ":" + official, "-d", name + ".jar"], root: root)
                    Issue.record("Official Kotlin must reject \(call)")
                } catch CommandRunnerError.nonZeroExit(let result) {
                    if name == "ErrorUse" {
                        #expect(result.stderr.contains("deprecated") && result.stderr.contains("error"))
                    } else {
                        #expect(result.stderr.contains("Unresolved reference") || result.stderr.contains("unresolved reference"))
                        #expect(result.stderr.contains("hidden"))
                    }
                }
            }
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func deprecatedConstFieldsAndAnnotationCarriersPreserveOwnersAndVisibility(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("deprecatedConstContracts.kt"), encoding: .utf8)
        try withWorkspace { root in
            let own = try ownStdlibLibrary().path
            let official = try m11Runtime()
            let app = try m22Build(root: root, sources: [("hello.kt", source)], name: "api", mode: mode, classpath: [own])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let inspector = #"""
            import java.lang.reflect.*;
            public class ConstInspect {
                static void check(Class<?> owner, String getter, String message, boolean hidden) throws Exception {
                    Method method = owner.getDeclaredMethod(getter + "$annotations");
                    if (Modifier.isPrivate(method.getModifiers()) != hidden || !Modifier.isStatic(method.getModifiers()) || !method.isSynthetic()) throw new AssertionError(owner);
                    if (!method.getAnnotation(kotlin.Deprecated.class).message().equals(message)) throw new AssertionError(message);
                    for (Method candidate : owner.getDeclaredMethods()) if (candidate.getName().equals(getter)) throw new AssertionError("const getter");
                }
                public static void main(String[] args) throws Exception {
                    check(HelloKt.class, "getTop", "top", false);
                    check(HelloKt.class, "getPrivateTop", "private-top", true);
                    check(ConstBox.Companion.class, "getValue", "class", false);
                    check(ConstBox.Companion.class, "getSecret", "private-class", true);
                    check(ConstFace.Companion.class, "getValue", "interface", false);
                    check(ConstFace.Companion.class, "getSecret", "private-interface", true);
                    check(ConstObject.class, "getValue", "object", false);
                    check(ConstObject.class, "getSecret", "private-object", true);
                    System.out.println("ok");
                }
            }
            """#
            try inspector.write(to: root.appendingPathComponent("ConstInspect.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", app.0.path + ":" + own, "ConstInspect.java"], root: root)
            for runtime in [own, official] {
                let result = try java(["-cp", root.path + ":" + app.0.path + ":" + runtime, "ConstInspect"])
                #expect(result.stdout == "ok\n")
                #expect(result.stderr.isEmpty)
            }
            let fields = [("HelloKt", ["public static final int top;", "private static final int privateTop;"]), ("ConstBox", ["public static final int value;", "private static final int secret;"]), ("ConstFace", ["public static final int value;"]), ("ConstFace$Companion", ["public static final int value;", "private static final int secret;"]), ("ConstObject", ["public static final int value;", "private static final int secret;"])]
            for (owner, declarations) in fields {
                let result = try jvmTool("javap", ["-p", "-v", "-cp", app.0.path, owner], root: root)
                for declaration in declarations {
                    let section = result.stdout.components(separatedBy: "\n\n").first { $0.contains("  " + declaration + "\n") }
                    #expect(section?.contains("Deprecated: true") == true, "\(owner).\(declaration)")
                }
            }
            try "class ConstUse { int use() { return HelloKt.top + ConstBox.value + ConstFace.value + ConstFace.Companion.value + ConstObject.value; } }".write(to: root.appendingPathComponent("ConstUse.java"), atomically: true, encoding: .utf8)
            let warning = try jvmTool("javac", ["-Xlint:deprecation", "-cp", app.0.path + ":" + own, "ConstUse.java"], root: root)
            #expect(warning.stderr.components(separatedBy: "[deprecation]").count - 1 == 5, "\(warning.stderr)")
        }
    }

    @Test(arguments: [
        "@Deprecated(12) fun old() = 1",
        "@Deprecated(\"x\", replaceWith = 12) fun old() = 1",
        "@Deprecated(\"x\", level = \"ERROR\") fun old() = 1",
        "fun old(@Deprecated(\"x\") value: Int) = value",
        "class Old { @field:Deprecated(\"x\") val value = 1 }",
        "@Deprecated(\"x\", level = DeprecationLevel.ERROR) fun old() = 1; fun main() { println(old()) }",
        "@Deprecated(\"x\", level = DeprecationLevel.HIDDEN) fun old() = 1; fun main() { println(old()) }",
    ], [EmitMode.jvmClass, .jvmJar])
    func deprecatedAnnotationsRejectInvalidArgumentsTargetsAndUses(source: String, mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode, classpath: [try ownStdlibLibrary().path])
            #expect(result.0 != 0)
            #expect(result.1.contains { $0.severity == .error && $0.code != "KSWIFTK-JVM-0001" }, "\(result.1.map(\.message))")
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path))
        }
    }
}
#endif
