@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func kClassModalityAndSingletons(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KClass
            import kotlin.reflect.typeOf

            class Plain
            open class Open
            abstract class Abstract
            interface Iface
            fun interface FunIface { fun run() }
            data class Data(val value: Int)
            sealed class Empty
            sealed class Root
            open class Child : Root()
            class Grandchild : Child()
            object Leaf : Root()
            sealed interface SealedIface
            class Impl : SealedIface
            var initialized = 0
            object Obj {
                init { initialized += 1 }
                val value = 42
            }
            class Owner { companion object { val value = 7 } }

            fun flags(k: KClass<*>) {
                println(k.isFinal)
                println(k.isOpen)
                println(k.isAbstract)
                println(k.isSealed)
            }
            fun <T : Any> instance(k: KClass<T>): T? = k.objectInstance
            fun main() {
                val classifier = typeOf<Root>().classifier as KClass<*>
                println(classifier.sealedSubclasses.size)
                println(classifier.isSealed)
                flags(Plain::class)
                flags(Data::class)
                flags(Obj::class)
                flags(Open::class)
                flags(Abstract::class)
                flags(Iface::class)
                flags(FunIface::class)
                flags(Empty::class)
                flags(SealedIface::class)
                val erased: KClass<*> = Obj::class
                println(initialized)
                println(erased.objectInstance === Obj)
                println(initialized)
                val nullableClassifier = typeOf<Obj?>().classifier as KClass<*>
                println(nullableClassifier == Obj::class)
                println(nullableClassifier.objectInstance === Obj)
                val typed: Obj? = instance(Obj::class)
                println(typed?.value)
                println(Plain::class.objectInstance == null)
                println(Owner.Companion::class.objectInstance === Owner.Companion)
                println(Owner.Companion::class.objectInstance?.value)
                println(Empty::class.sealedSubclasses.size)
                val subclasses: List<KClass<out Root>> = Root::class.sealedSubclasses
                println(subclasses.size)
                println(subclasses.contains(Child::class))
                println(subclasses.contains(Leaf::class))
                println(subclasses.contains(Grandchild::class))
                println(Root::class.sealedSubclasses.size)
                println(Plain::class.sealedSubclasses.size)
                println(SealedIface::class.sealedSubclasses.contains(Impl::class))
                flags(Plain()::class)
                flags(Open()::class)
            }
            """,
            expectedOutput: "2\ntrue\ntrue\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\ntrue\n0\ntrue\n1\ntrue\ntrue\n42\ntrue\ntrue\n7\n0\n2\ntrue\ntrue\nfalse\n2\n0\ntrue\ntrue\nfalse\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\n",
            moduleName: "KUU1315KClassModality",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }

    @Test(arguments: [true, false])
    func kClassObjectInstancePropagatesInitializationFailure(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KClass
            object Broken { init { throw IllegalStateException("init failed") } }
            fun main() {
                val k: KClass<*> = Broken::class
                try {
                    k.objectInstance
                    println("unexpected")
                } catch (e: IllegalStateException) {
                    println(e.message)
                }
            }
            """,
            expectedOutput: "init failed\n",
            moduleName: "KUU1315ObjectInitFailure",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }

    @Test func kClassImportedObjectInstance() throws {
        try withCompiledLibrary(source: """
            package reflectionLib
            var initialized = 0
            object Obj {
                init { initialized += 1 }
                val value = 42
            }
            class Owner { companion object { val value = 7 } }
            sealed class Root
            class Child : Root()
            """, moduleName: "KClassSingletonLibrary") { library in
            try withTemporaryFile(contents: """
                import kotlin.reflect.KClass
                import reflectionLib.*
                fun main() {
                    val k: KClass<*> = Obj::class
                    println(initialized)
                    println(k.objectInstance === Obj)
                    println(initialized)
                    println(Obj::class.objectInstance?.value)
                    println(Owner.Companion::class.objectInstance === Owner.Companion)
                    println(Owner.Companion::class.objectInstance?.value)
                    println(Root::class.sealedSubclasses.contains(Child::class))
                }
                """) { source in
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let options = CompilerOptions(
                    moduleName: "KClassSingletonConsumer", inputs: [source], outputPath: output,
                    emit: .executable, searchPaths: [library], target: defaultTargetTriple()
                )
                try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stdout == "0\ntrue\n1\n42\ntrue\n7\ntrue\n")
            }
        }
    }
}
