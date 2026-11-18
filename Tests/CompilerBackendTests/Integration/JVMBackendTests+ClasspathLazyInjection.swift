#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func oversizedClasspathFallsBackToReferencedLazyInjection() throws {
        try withWorkspace { root in
            let dependency = try javaFixture(root)

            let eager = try JVMClasspathIndex.load([dependency.path])
            #expect(eager.lazyClassNames.isEmpty)
            #expect(eager.classes["dep/Counter"] != nil)

            let lazy = try JVMClasspathIndex.load(
                [dependency.path], automaticLazyClasspathMemberLimit: 1
            )
            #expect(lazy.classes["dep/Counter"] != nil)
            #expect(lazy.lazyClassNames.contains("dep/Counter"))
            #expect(lazy.lazyClassNames.contains("dep/Child"))
        }
    }

    @Test
    func lazyFileFacadeMembersAreReachableFromImports() throws {
        try withWorkspace { root in
            try """
            package fixture

            class Widget

            suspend fun Widget.render(content: (Int, Int) -> Unit) {
                content(20, 22)
            }
            """.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Provider.kt", "-d", "provider.jar"], root: root)
            let provider = root.appendingPathComponent("provider.jar")
            let index = try JVMClasspathIndex.load(
                [provider.path], automaticLazyClasspathMemberLimit: 1
            )
            #expect(index.lazyClassNames.contains("fixture/ProviderKt"))
            #expect(index.lazyClassNames.contains("fixture/Widget"))

            let consumerPath = root.appendingPathComponent("consumer.kt").path
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "LazyFacadeTest",
                    inputs: [consumerPath],
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
            _ = ctx.sourceManager.addFile(path: consumerPath, contents: Data("""
            import fixture.Widget
            import fixture.render

            suspend fun Widget.probe() {
                render { left, right -> println(left + right) }
            }
            """.utf8))
            try index.inject(into: ctx)

            let facadePath = "<kswiftk-jvm-import>/fixture/ProviderKt.kt"
            let facadeID = try #require(ctx.sourceManager.fileID(forPath: facadePath))
            let facade = String(decoding: ctx.sourceManager.contents(of: facadeID), as: UTF8.self)
            #expect(facade.contains("suspend fun fixture.Widget.`render`"))
            #expect(facade.contains("(kotlin.Int, kotlin.Int) -> kotlin.Unit"))
            #expect(ctx.sourceManager.fileID(forPath: "<kswiftk-jvm-import>/fixture/Widget.kt") != nil)
        }
    }

    @Test
    func demandDecodesOnlyReferencedKotlinClasspathClasses() throws {
        try withWorkspace { root in
            let kotlinSrc = root.appendingPathComponent("kotlin-src")
            let depSrc = root.appendingPathComponent("dep-src")
            let kotlinPackage = kotlinSrc.appendingPathComponent("kotlin")
            let concurrentPackage = kotlinPackage.appendingPathComponent("concurrent")
            let functionsPackage = kotlinPackage.appendingPathComponent("jvm").appendingPathComponent("functions")
            let depPackage = depSrc.appendingPathComponent("dep")
            try FileManager.default.createDirectory(at: concurrentPackage, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: functionsPackage, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: depPackage, withIntermediateDirectories: true)
            let sources: [(URL, String)] = [
                (concurrentPackage.appendingPathComponent("LazyThreadSafetyMode.java"), """
                package kotlin.concurrent;
                public enum LazyThreadSafetyMode { PUBLICATION, SYNCHRONIZED }
                """),
                (kotlinPackage.appendingPathComponent("Base.java"), """
                package kotlin;
                public class Base {
                    public int value() { return 1; }
                    public Consumed consumed() { return null; }
                }
                """),
                (kotlinPackage.appendingPathComponent("Consumed.java"), """
                package kotlin;
                public class Consumed {}
                """),
                (functionsPackage.appendingPathComponent("Function1.java"), """
                package kotlin.jvm.functions;
                public interface Function1<P1, R> { R invoke(P1 p1); }
                """),
                (kotlinPackage.appendingPathComponent("Unused.java"), """
                package kotlin;
                public class Unused {}
                """),
                (depPackage.appendingPathComponent("UsesKotlinType.java"), """
                package dep;
                public class UsesKotlinType {
                    public kotlin.concurrent.LazyThreadSafetyMode mode() { return kotlin.concurrent.LazyThreadSafetyMode.SYNCHRONIZED; }
                    public kotlin.Base base() { return new kotlin.Base(); }
                }
                """),
                (depPackage.appendingPathComponent("UsesFunction.java"), """
                package dep;
                public class UsesFunction {
                    public kotlin.jvm.functions.Function1<Integer, Integer> compose() { return null; }
                }
                """),
                (depPackage.appendingPathComponent("Sub.java"), """
                package dep;
                public class Sub extends kotlin.Base {}
                """),
            ]
            for (url, source) in sources {
                try source.write(to: url, atomically: true, encoding: .utf8)
            }
            let classes = root.appendingPathComponent("classes")
            try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
            let compiled = try jvmTool("javac", ["-d", classes.path] + sources.map { $0.0.path }, root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let archived = try jvmTool("jar", ["cf", "mixed.jar", "-C", classes.path, "."], root: root)
            try #require(archived.exitCode == 0, "\(archived.stderr)")

            let index = try JVMClasspathIndex.load([root.appendingPathComponent("mixed.jar").path])
            #expect(index.classes["dep/UsesKotlinType"] != nil)
            #expect(index.classes["dep/Sub"] != nil)
            #expect(index.classes["dep/Sub"]?.superclass == "kotlin/Base")
            #expect(index.classes["kotlin/Base"] != nil)
            #expect(index.classes["kotlin/concurrent/LazyThreadSafetyMode"] != nil)
            #expect(index.classes["kotlin/Consumed"] != nil)
            #expect(index.classes["kotlin/jvm/functions/Function1"] != nil)
            #expect(index.hasClassFile("kotlin/jvm/functions/Function1"))
            #expect(index.classes["kotlin/Unused"] == nil)
        }
    }
}
#endif
