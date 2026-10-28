#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    private func genericNestedLibrarySource() -> String {
        """
        package external
        class GenericOuter<T>(val value: T) {
            inner class Inner<U>(val other: U)
            class Static<W>(val value: W)
            private class Hidden
        }
        """
    }

    private func ownerSignaturesSource() -> String {
        """
        package api
        import external.GenericOuter
        interface ExternalOwnerSignatures {
            fun inner(): GenericOuter<String>.Inner<Int>
            fun nested(): GenericOuter.Static<String>
        }
        """
    }

    private func writeJavaNestedClassFixtures(to root: URL) throws {
        let source = root.appendingPathComponent("external/MetadataOuter.java")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        package external;
        public class MetadataOuter {
            public static class Visible {}
            protected static class Protected {}
            private static class Hidden {}
            public Object create() {
                class Local {}
                return new Object() {};
            }
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        _ = try jvmTool("javac", ["--release", "21", "-d", "library-classes", "external/MetadataOuter.java"], root: root)
    }

    private func compileJavaNestedConsumer(artifact: URL, dependency: URL?, output: URL, root: URL) throws -> CommandResult {
        let source = root.appendingPathComponent("ExternalConsumer.java")
        try """
        import api.ExternalOwnerSignatures;
        import external.GenericOuter;

        public class ExternalConsumer {
            static GenericOuter.Inner inner(ExternalOwnerSignatures value) { return value.inner(); }
            static GenericOuter.Static<String> nested(ExternalOwnerSignatures value) { return value.nested(); }
            public static void main(String[] args) throws Exception {
                System.out.println(ExternalOwnerSignatures.class.getMethod("inner").getGenericReturnType().getTypeName());
                System.out.println(ExternalOwnerSignatures.class.getMethod("nested").getGenericReturnType().getTypeName());
            }
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let classpath = ([artifact] + (dependency.map { [$0] } ?? [])).map(\.path).joined(separator: ":")
        return try jvmTool("javac", ["--release", "21", "-classpath", classpath, "-d", output.path, source.path], root: root)
    }

    private func assertJavaNestedConsumerLoads(artifact: URL, dependency: URL?, javaOutput: URL) throws {
        let classpath = ([javaOutput, artifact] + (dependency.map { [$0] } ?? [])).map(\.path).joined(separator: ":")
        let execution = try java(["-cp", classpath, "ExternalConsumer"])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        let lines = execution.stdout.split(separator: "\n").map(String.init)
        #expect(lines.count == 2, "\(execution.stdout)")
        #expect(lines.first?.contains("external.GenericOuter") == true && lines.first?.contains("Inner") == true)
        #expect(lines.last?.contains("external.GenericOuter") == true && lines.last?.contains("Static") == true)
    }

    private func nestedOrderLibrary(root: URL, nestedName: String) throws -> URL {
        let source = root.appendingPathComponent("\(nestedName).kt")
        try "package external\nclass OrderedOuter { class \(nestedName) }\n"
            .write(to: source, atomically: true, encoding: .utf8)
        let classes = root.appendingPathComponent("\(nestedName)-classes", isDirectory: true)
        try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
        _ = try jvmTool("kotlinc", [source.path, "-d", classes.path], root: root)
        let jar = root.appendingPathComponent("\(nestedName).jar")
        _ = try jvmTool("jar", ["cf", jar.path, "-C", classes.path, "."], root: root)
        return jar
    }

    @Test
    func resolvesGenericNestedTypesFromSourceClassDirectoryAndJar() throws {
        try withWorkspace { root in
            let librarySource = genericNestedLibrarySource()
            let apiSource = ownerSignaturesSource()
            let sourceRoute = try m22Build(
                root: root,
                sources: [("source/GenericOuter.kt", librarySource), ("source/ExternalOwnerSignatures.kt", apiSource)],
                name: "source-api.jar"
            )
            try #require(sourceRoute.1 == 0, "\(sourceRoute.2.map(\.message))")

            try librarySource.write(to: root.appendingPathComponent("GenericOuter.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["GenericOuter.kt", "-d", "library-classes"], root: root)
            try writeJavaNestedClassFixtures(to: root)
            _ = try jvmTool("jar", ["cf", "library.jar", "-C", "library-classes", "."], root: root)
            let classDirectory = root.appendingPathComponent("library-classes", isDirectory: true)
            let libraryJar = root.appendingPathComponent("library.jar")

            let index = try JVMClasspathIndex.load([classDirectory.path])
            #expect(index.classes["external/GenericOuter"]?.classTypeParameterNames == ["T"])
            #expect(index.classes["external/GenericOuter$Inner"]?.classTypeParameterNames == ["U"])
            #expect(index.classes["external/GenericOuter$Static"]?.classTypeParameterNames == ["W"])
            #expect(index.classes["external/GenericOuter$Hidden"] == nil)
            #expect(index.classes["external/MetadataOuter$Visible"] != nil)
            #expect(index.classes["external/MetadataOuter$Protected"] != nil)
            #expect(index.classes["external/MetadataOuter$Hidden"] == nil)
            let metadataNested = Set(index.classes.keys.filter { $0.hasPrefix("external/MetadataOuter$") })
            #expect(metadataNested == ["external/MetadataOuter$Visible", "external/MetadataOuter$Protected"])

            try apiSource.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            let reference = try jvmTool("kotlinc", ["consumer.kt", "-classpath", libraryJar.path, "-d", "reference-api.jar"], root: root)
            #expect(reference.exitCode == 0, "\(reference.stderr)")

            let sourceJavaOutput = root.appendingPathComponent("source-java", isDirectory: true)
            let sourceJava = try compileJavaNestedConsumer(artifact: sourceRoute.0, dependency: nil, output: sourceJavaOutput, root: root)
            #expect(sourceJava.exitCode == 0, "\(sourceJava.stderr)")
            try assertJavaNestedConsumerLoads(artifact: sourceRoute.0, dependency: nil, javaOutput: sourceJavaOutput)

            let classRoot = root.appendingPathComponent("class-route", isDirectory: true)
            try FileManager.default.createDirectory(at: classRoot, withIntermediateDirectories: true)
            let classResult = try compile(apiSource, root: classRoot, mode: .jvmClass, classpath: [classDirectory.path])
            try #require(classResult.0 == 0, "\(classResult.1.map(\.message))")
            let classArtifact = classRoot.appendingPathComponent("classes", isDirectory: true)
            let classJavaOutput = root.appendingPathComponent("class-java", isDirectory: true)
            let classJava = try compileJavaNestedConsumer(artifact: classArtifact, dependency: classDirectory, output: classJavaOutput, root: root)
            #expect(classJava.exitCode == 0, "\(classJava.stderr)")
            try assertJavaNestedConsumerLoads(artifact: classArtifact, dependency: classDirectory, javaOutput: classJavaOutput)

            let jarRoot = root.appendingPathComponent("jar-route", isDirectory: true)
            try FileManager.default.createDirectory(at: jarRoot, withIntermediateDirectories: true)
            let jarResult = try compile(apiSource, root: jarRoot, mode: .jvmJar, classpath: [libraryJar.path])
            try #require(jarResult.0 == 0, "\(jarResult.1.map(\.message))")
            let jarArtifact = jarRoot.appendingPathComponent("hello.jar")
            let jarJavaOutput = root.appendingPathComponent("jar-java", isDirectory: true)
            let jarJava = try compileJavaNestedConsumer(artifact: jarArtifact, dependency: libraryJar, output: jarJavaOutput, root: root)
            #expect(jarJava.exitCode == 0, "\(jarJava.stderr)")
            try assertJavaNestedConsumerLoads(artifact: jarArtifact, dependency: libraryJar, javaOutput: jarJavaOutput)
        }
    }

    @Test
    func missingAndInaccessibleImportedNestedTypesRemainUnresolved() throws {
        try withWorkspace { root in
            try genericNestedLibrarySource().write(to: root.appendingPathComponent("GenericOuter.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["GenericOuter.kt", "-d", "library.jar"], root: root)
            let source = """
            import external.GenericOuter
            interface InvalidNestedTypes {
                fun missing(): GenericOuter.Missing
                fun hidden(): GenericOuter.Hidden
            }
            """
            let result = try compile(source, root: root, mode: .jvmJar, classpath: [root.appendingPathComponent("library.jar").path])
            #expect(result.0 != 0)
            #expect(result.1.filter { $0.severity == .error && $0.code == "KSWIFTK-SEMA-0025" }.count >= 2, "\(result.1.map(\.message))")
        }
    }

    @Test
    func nestedClassMetadataFollowsClasspathEntryOrder() throws {
        try withWorkspace { root in
            let first = try nestedOrderLibrary(root: root, nestedName: "First")
            let second = try nestedOrderLibrary(root: root, nestedName: "Second")
            let firstWins = try JVMClasspathIndex.load([first.path, second.path])
            #expect(firstWins.classes["external/OrderedOuter$First"] != nil)
            #expect(firstWins.classes["external/OrderedOuter$Second"] == nil)
            let secondWins = try JVMClasspathIndex.load([second.path, first.path])
            #expect(secondWins.classes["external/OrderedOuter$Second"] != nil)
            #expect(secondWins.classes["external/OrderedOuter$First"] == nil)
        }
    }
}
#endif
