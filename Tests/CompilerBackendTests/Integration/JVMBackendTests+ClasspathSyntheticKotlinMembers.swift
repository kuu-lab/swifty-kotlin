#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    private func externalReifiedCodecLibraryJar(_ root: URL) throws -> URL {
        try """
        package fixture

        interface Strategy<T>

        abstract class Codec {
            fun <T> encode(strategy: Strategy<T>, value: T): String = "two"
            inline fun <reified T> encode(value: T): String = "one"
            companion object Default : Codec()
        }
        """.write(to: root.appendingPathComponent("CodecLibrary.kt"), atomically: true, encoding: .utf8)
        _ = try jvmTool("kotlinc", ["CodecLibrary.kt", "-d", "codec-library.jar"], root: root)
        return root.appendingPathComponent("codec-library.jar")
    }

    private func externalHiddenDeprecatedLibraryJar(_ root: URL) throws -> URL {
        try """
        package fixture

        @Deprecated("hidden", level = DeprecationLevel.HIDDEN)
        fun hidden(): Int = 1

        fun visible(): Int = 2

        class DeprecatedProperties {
            @Deprecated("hidden", level = DeprecationLevel.HIDDEN)
            val hidden: Int = 1
            val visible: Int = 2
        }
        """.write(to: root.appendingPathComponent("HiddenLibrary.kt"), atomically: true, encoding: .utf8)
        _ = try jvmTool("kotlinc", ["HiddenLibrary.kt", "-d", "hidden-library.jar"], root: root)
        return root.appendingPathComponent("hidden-library.jar")
    }

    private func externalReifiedFileFacadeLibraryJar(_ root: URL) throws -> URL {
        try """
        package fixture

        import kotlin.reflect.KClass

        open class ViewModel
        class Lazy<T : Any>(val type: KClass<T>)
        class Host

        inline fun <reified VM : ViewModel> Host.viewModels(factoryProducer: () -> Any = { Any() }): Lazy<VM> = Lazy(VM::class)

        inline fun <reified VM : ViewModel> Host.activityViewModels(factoryProducer: () -> Any = { Any() }, extrasProducer: () -> Any = { Any() }): Lazy<VM> = Lazy(VM::class)
        """.write(to: root.appendingPathComponent("ViewModelLazy.kt"), atomically: true, encoding: .utf8)
        _ = try jvmTool("kotlinc", ["ViewModelLazy.kt", "-d", "viewmodel-lazy.jar"], root: root)
        return root.appendingPathComponent("viewmodel-lazy.jar")
    }

    private func externalReifiedFunctionTypeReceiverLibraryJar(_ root: URL) throws -> URL {
        try """
        package fixture

        import kotlin.reflect.KClass

        class Lazy<T : Any>(val type: KClass<T>)
        open class ViewModel

        inline fun <reified VM : ViewModel> (() -> Any).viewModels(factoryProducer: () -> Any = { Any() }): Lazy<VM> = Lazy(VM::class)
        """.write(to: root.appendingPathComponent("FunctionTypeReceiver.kt"), atomically: true, encoding: .utf8)
        _ = try jvmTool("kotlinc", ["FunctionTypeReceiver.kt", "-d", "function-type-receiver.jar"], root: root)
        return root.appendingPathComponent("function-type-receiver.jar")
    }

    private func externalReifiedCallbackLibraryJar(_ root: URL) throws -> URL {
        try """
        package fixture

        import kotlin.reflect.KClass

        class Callback
        open class ViewModel
        class Lazy<T : Any>(val type: KClass<T>)
        class Host

        inline fun <reified VM : ViewModel> Host.viewModels(factoryProducer: () -> Callback = { Callback() }): Lazy<VM> = Lazy(VM::class)
        """.write(to: root.appendingPathComponent("CallbackLazy.kt"), atomically: true, encoding: .utf8)
        _ = try jvmTool("kotlinc", ["CallbackLazy.kt", "-d", "callback-lazy.jar"], root: root)
        return root.appendingPathComponent("callback-lazy.jar")
    }

    private func externalJvmSyntheticPropertyLibraryJar(_ root: URL) throws -> URL {
        try """
        package fixture

        import kotlin.jvm.JvmSynthetic

        class Properties {
            @get:JvmSynthetic
            val hidden: Int = 42
            val visible: Int = 3
        }

        @get:JvmSynthetic
        val topHidden: Int = 5
        val topVisible: Int = 6
        """.write(to: root.appendingPathComponent("SyntheticProperties.kt"), atomically: true, encoding: .utf8)
        _ = try jvmTool("kotlinc", ["SyntheticProperties.kt", "-d", "synthetic-properties.jar"], root: root)
        return root.appendingPathComponent("synthetic-properties.jar")
    }

    @Test
    func externalKotlinSyntheticReifiedFileFacadeExtensionResolves() throws {
        try withWorkspace { root in
            let library = try externalReifiedFileFacadeLibraryJar(root)
            let compiled = try compile("""
            package probe

            import fixture.Host
            import fixture.Lazy
            import fixture.ViewModel
            import fixture.activityViewModels
            import fixture.viewModels

            class MyViewModel : ViewModel()

            fun main() {
                val host = Host()
                val model: Lazy<MyViewModel> = host.viewModels()
                val other: Lazy<MyViewModel> = host.activityViewModels()
            }
            """, root: root, mode: .jvmJar, classpath: [library.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
        }
    }

    @Test
    func externalKotlinSyntheticReifiedFunctionTypeReceiverParses() throws {
        try withWorkspace { root in
            let library = try externalReifiedFunctionTypeReceiverLibraryJar(root)
            let compiled = try compile("""
            package probe

            import fixture.Lazy
            import fixture.ViewModel
            import fixture.viewModels

            class MyViewModel : ViewModel()

            fun main() {
                val factory: () -> Any = { Any() }
                val model: Lazy<MyViewModel> = factory.viewModels()
            }
            """, root: root, mode: .jvmJar, classpath: [library.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
        }
    }

    @Test
    func externalKotlinSyntheticReifiedCallbackTypeJoinsLazyClosure() throws {
        try withWorkspace { root in
            let library = try externalReifiedCallbackLibraryJar(root)
            let consumerPath = root.appendingPathComponent("consumer.kt").path
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "CallbackLazyTest",
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
            _ = ctx.sourceManager.addFile(path: consumerPath, contents: Data("import fixture.viewModels\nfun main() {}".utf8))
            let index = try JVMClasspathIndex.load([library.path], automaticLazyClasspathMemberLimit: 0)
            try index.inject(into: ctx)

            let callbackID = try #require(ctx.sourceManager.fileID(forPath: "<kswiftk-jvm-import>/fixture/Callback.kt"))
            let callback = String(decoding: ctx.sourceManager.contents(of: callbackID), as: UTF8.self)
            #expect(callback.contains("class `Callback`"))
        }
    }

    @Test
    func externalKotlinSyntheticReifiedMemberResolvesBesideOverload() throws {
        try withWorkspace { root in
            let library = try externalReifiedCodecLibraryJar(root)
            let compiled = try compile("""
            import fixture.Codec
            fun main() {
                val map = mutableMapOf<String, String>()
                map["a"] = "b"
                println(Codec.encode(map))
            }
            """, root: root, mode: .jvmJar, classpath: [library.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let runtime = try m11Runtime()
            let execution = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + library.path + ":" + runtime, "HelloKt"])
            #expect(execution.stdout == "one\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test
    func classpathHiddenDeprecatedSyntheticMemberStaysHidden() throws {
        try withWorkspace { root in
            let library = try externalHiddenDeprecatedLibraryJar(root)
            let consumerPath = root.appendingPathComponent("consumer.kt").path
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "HiddenDeprecationTest",
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
            _ = ctx.sourceManager.addFile(path: consumerPath, contents: Data("import fixture.visible\nfun main() { println(visible()) }".utf8))
            let index = try JVMClasspathIndex.load([library.path])
            try index.inject(into: ctx)

            let facadePath = "<kswiftk-jvm-import>/fixture/HiddenLibraryKt.kt"
            let facadeID = try #require(ctx.sourceManager.fileID(forPath: facadePath))
            let facade = String(decoding: ctx.sourceManager.contents(of: facadeID), as: UTF8.self)
            #expect(facade.contains("`visible`"))
            #expect(!facade.contains("`hidden`"))

            let classPath = "<kswiftk-jvm-import>/fixture/DeprecatedProperties.kt"
            let classID = try #require(ctx.sourceManager.fileID(forPath: classPath))
            let classSource = String(decoding: ctx.sourceManager.contents(of: classID), as: UTF8.self)
            #expect(classSource.contains("`visible`"))
            #expect(!classSource.contains("`hidden`"))
        }
    }

    @Test
    func externalKotlinJvmSyntheticPropertyReadsMatchKotlinc() throws {
        try withWorkspace { root in
            let library = try externalJvmSyntheticPropertyLibraryJar(root)
            let compiled = try compile("""
            import fixture.Properties
            import fixture.topHidden
            import fixture.topVisible

            fun main() {
                val properties = Properties()
                println(properties.hidden)
                println(properties.visible)
                println(topHidden)
                println(topVisible)
            }
            """, root: root, mode: .jvmJar, classpath: [library.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let runtime = try m11Runtime()
            let dependencies = library.path + ":" + runtime
            let generated = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + dependencies, "HelloKt"])
            #expect(generated.stderr.isEmpty)
            #expect(generated.stdout == "42\n3\n5\n6\n")

            let referenceCompile = try jvmTool("kotlinc", ["hello.kt", "-cp", library.path, "-d", "reference.jar"], root: root)
            #expect(referenceCompile.exitCode == 0, "\(referenceCompile.stderr)")
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + dependencies, "HelloKt"])
            #expect(reference.stderr.isEmpty)
            #expect(reference.stdout == generated.stdout)

            let javaProbe = root.appendingPathComponent("JavaProbe.java")
            try """
            import fixture.Properties;
            import fixture.SyntheticPropertiesKt;

            public class JavaProbe {
                public static void main(String[] args) {
                    System.out.println(new Properties().getHidden());
                    System.out.println(SyntheticPropertiesKt.getTopHidden());
                }
            }
            """.write(to: javaProbe, atomically: true, encoding: .utf8)
            var rejected = false
            do {
                _ = try javac(["-cp", library.path, "-d", root.appendingPathComponent("java-probe-out").path, javaProbe.path])
            } catch CommandRunnerError.nonZeroExit(let rejection) {
                rejected = true
                #expect(rejection.stderr.contains("cannot find symbol")
                    || rejection.stdout.contains("cannot find symbol"))
            }
            #expect(rejected, "javac resolved @get:JvmSynthetic property getters")
        }
    }
}
#endif
