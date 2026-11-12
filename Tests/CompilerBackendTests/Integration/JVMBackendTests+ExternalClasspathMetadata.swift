#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    private func externalJavaAnnotationJar(_ root: URL) throws -> URL {
        let fixture = root.appendingPathComponent("fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        try """
        package fixture;
        import java.lang.annotation.*;
        @Retention(RetentionPolicy.RUNTIME)
        @Target({ElementType.FIELD, ElementType.METHOD, ElementType.PARAMETER})
        public @interface Marker {
            String[] names() default {"--default"};
            boolean enabled() default true;
            int count() default 3;
        }
        """.write(to: fixture.appendingPathComponent("Marker.java"), atomically: true, encoding: .utf8)
        _ = try jvmTool("javac", ["--release", "21", "-d", "annotation-classes", "fixture/Marker.java"], root: root)
        _ = try jvmTool("jar", ["cf", "annotations.jar", "-C", "annotation-classes", "."], root: root)
        return root.appendingPathComponent("annotations.jar")
    }

    private func externalReceiverLibraryJar(_ root: URL) throws -> URL {
        try """
        package dep
        class Builder { var enabled: Boolean = false }
        fun configure(block: Builder.() -> Unit): Boolean = Builder().apply(block).enabled
        """.write(to: root.appendingPathComponent("BuilderLibrary.kt"), atomically: true, encoding: .utf8)
        _ = try jvmTool("kotlinc", ["BuilderLibrary.kt", "-d", "builder-library.jar"], root: root)
        return root.appendingPathComponent("builder-library.jar")
    }

    private func externalNestedAnnotationLibraryJar(_ root: URL) throws -> URL {
        try """
        package fixture
        annotation class RestrictTo(vararg val value: Scope) {
            enum class Scope { LIBRARY, TESTS }
        }
        annotation class Inspectable(
            val valueType: ValueType = ValueType.INFERRED,
            val enumMapping: Array<EnumEntry> = [],
            val flagMapping: Array<FlagEntry> = []
        ) {
            enum class ValueType { NONE, INFERRED, INT_ENUM }
            annotation class EnumEntry(val name: String, val value: Int)
            annotation class FlagEntry(val name: String, val target: Int, val mask: Int)
        }
        """.write(to: root.appendingPathComponent("NestedAnnotations.kt"), atomically: true, encoding: .utf8)
        _ = try jvmTool("kotlinc", ["NestedAnnotations.kt", "-d", "nested-annotations.jar"], root: root)
        return root.appendingPathComponent("nested-annotations.jar")
    }

    private func externalJavaValueAnnotationJar(_ root: URL) throws -> URL {
        let fixture = root.appendingPathComponent("fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        try """
        package fixture;
        import java.lang.annotation.*;
        @Retention(RetentionPolicy.RUNTIME)
        @Target({ElementType.METHOD})
        public @interface JavaValue { String[] value(); int count() default 1; }
        """.write(to: fixture.appendingPathComponent("JavaValue.java"), atomically: true, encoding: .utf8)
        try """
        package fixture;
        import java.lang.annotation.*;
        @Retention(RetentionPolicy.RUNTIME)
        @Target({ElementType.METHOD})
        public @interface LongMin { long value() default Long.MIN_VALUE; }
        """.write(to: fixture.appendingPathComponent("LongMin.java"), atomically: true, encoding: .utf8)
        _ = try jvmTool("javac", ["--release", "21", "-d", "annotation-classes", "fixture/JavaValue.java", "fixture/LongMin.java"], root: root)
        _ = try jvmTool("jar", ["cf", "java-value-annotations.jar", "-C", "annotation-classes", "."], root: root)
        return root.appendingPathComponent("java-value-annotations.jar")
    }

    @Test
    func externalJavaAnnotationImportsElementsAndPlacesOnField() throws {
        try withWorkspace { root in
            let annotations = try externalJavaAnnotationJar(root)
            let compiled = try compile("""
            import fixture.Marker
            class Options {
                @Marker(names = ["--verbose"], enabled = false)
                var verbose: Boolean = false
            }
            fun main() { println(Options().verbose) }
            """, root: root, mode: .jvmJar, classpath: [annotations.path])
            try #require(compiled.0 == 0, "\(compiled.1.map { $0.message })")

            let hello = root.appendingPathComponent("hello.jar")
            let runtime = try m11Runtime()
            let execution = try java(["-cp", hello.path + ":" + annotations.path + ":" + runtime, "HelloKt"])
            #expect(execution.stdout == "false\n")
            #expect(execution.stderr.isEmpty)

            let inspection = try javap(["-v", "-p", "-classpath", hello.path, "Options"])
            #expect(inspection.exitCode == 0, "\(inspection.stderr)")
            #expect(inspection.stdout.contains("private boolean verbose;"))
            #expect(inspection.stdout.contains("fixture.Marker("))
            #expect(inspection.stdout.contains("names=[\"--verbose\"]"))
            #expect(inspection.stdout.contains("enabled=false"))
            #expect(!inspection.stdout.contains("count=3"))
            #expect(!inspection.stdout.contains("getVerbose$annotations"))

            try """
            import fixture.Marker;
            import java.lang.reflect.Field;
            public class MarkerReader {
                public static void main(String[] args) throws Exception {
                    Field field = Class.forName("Options").getDeclaredField("verbose");
                    Marker marker = field.getAnnotation(Marker.class);
                    if (marker == null) throw new AssertionError("missing field annotation");
                    System.out.println(marker.names()[0] + ":" + marker.enabled() + ":" + marker.count());
                }
            }
            """.write(to: root.appendingPathComponent("MarkerReader.java"), atomically: true, encoding: .utf8)
            let readerClasses = root.appendingPathComponent("reader-classes")
            let classpath = [hello.path, annotations.path, runtime].joined(separator: ":")
            let readerCompile = try jvmTool("javac", ["--release", "21", "-cp", classpath, "-d", readerClasses.path, "MarkerReader.java"], root: root)
            #expect(readerCompile.exitCode == 0, "\(readerCompile.stderr)")
            let readerRun = try java(["-cp", readerClasses.path + ":" + classpath, "MarkerReader"])
            #expect(readerRun.exitCode == 0, "\(readerRun.stderr)")
            #expect(readerRun.stdout == "--verbose:false:3\n")
        }
    }

    @Test
    func kotlinNestedAnnotationTypesExposeEntriesAndNestedAnnotations() throws {
        try withWorkspace { root in
            let library = try externalNestedAnnotationLibraryJar(root)
            let index = try JVMClasspathIndex.load([library.path])
            #expect(index.classes["fixture/RestrictTo"]?.hasKotlinMetadata == true)
            #expect(index.classes["fixture/RestrictTo"]?.kotlinAnnotationVarargElementNames == ["value"])

            let compiled = try compile("""
            import fixture.Inspectable
            import fixture.RestrictTo

            @RestrictTo(RestrictTo.Scope.LIBRARY)
            @Inspectable(
                valueType = Inspectable.ValueType.INT_ENUM,
                enumMapping = [Inspectable.EnumEntry(name = "A", value = 1)],
                flagMapping = [Inspectable.FlagEntry(name = "F", target = 1, mask = 1)]
            )
            fun answer(): Int = 42

            fun main() { println(answer()) }
            """, root: root, mode: .jvmJar, classpath: [library.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let runtime = try m11Runtime()
            let execution = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + library.path + ":" + runtime, "HelloKt"])
            #expect(execution.stdout == "42\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test
    func javaValueArrayAnnotationUsesVarargBindingAndLongMinDefault() throws {
        try withWorkspace { root in
            let annotations = try externalJavaValueAnnotationJar(root)
            let compiled = try compile("""
            import fixture.JavaValue
            import fixture.LongMin

            @JavaValue("x", count = 2)
            @LongMin()
            fun answer(): Int = 42

            fun main() { println(answer()) }
            """, root: root, mode: .jvmJar, classpath: [annotations.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let runtime = try m11Runtime()
            let hello = root.appendingPathComponent("hello.jar")
            let execution = try java(["-cp", hello.path + ":" + annotations.path + ":" + runtime, "HelloKt"])
            #expect(execution.stdout == "42\n")
            #expect(execution.stderr.isEmpty)

            let inspection = try javap(["-v", "-p", "-classpath", hello.path, "HelloKt"])
            #expect(inspection.exitCode == 0, "\(inspection.stderr)")
            #expect(inspection.stdout.contains("fixture.JavaValue("))
            #expect(inspection.stdout.contains("value=[\"x\"]"))
            #expect(inspection.stdout.contains("count=2"))
        }
    }

    @Test
    func externalKotlinReceiverFunctionCallsMatchKotlinc() throws {
        try withWorkspace { root in
            let library = try externalReceiverLibraryJar(root)
            let compiled = try compile("""
            import dep.configure
            fun main() { println(configure { enabled = true }) }
            """, root: root, mode: .jvmJar, classpath: [library.path])
            try #require(compiled.0 == 0, "\(compiled.1.map { $0.message })")

            let referenceCompile = try jvmTool("kotlinc", ["hello.kt", "-cp", library.path, "-d", "reference.jar"], root: root)
            #expect(referenceCompile.exitCode == 0, "\(referenceCompile.stderr)")
            let runtime = try m11Runtime()
            let dependencies = library.path + ":" + runtime
            let generated = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + dependencies, "HelloKt"])
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + dependencies, "HelloKt"])
            #expect(generated.stderr.isEmpty)
            #expect(generated.stdout == reference.stdout)
            #expect(reference.stdout == "true\n")
        }
    }
}
#endif
