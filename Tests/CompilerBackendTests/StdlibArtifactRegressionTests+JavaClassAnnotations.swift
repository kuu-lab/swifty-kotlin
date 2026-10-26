@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {
    /// KUU-2345: java.lang.Class.annotations exposes typed runtime annotations with JVM inheritance rules.
    @Test(arguments: [false, true], [0, 2])
    func javaClassAnnotationsAcrossStdlibSurfaces(fromSource: Bool, optimization: Int) throws {
        let source = """
        import java.lang.annotation.Inherited

        interface A

        data class B<out T : A>(val a: T)

        annotation class Anno

        @Anno
        data class C(val a: Anno)

        data class D<T : Int>(val t: T)

        @Inherited
        @Retention(AnnotationRetention.RUNTIME)
        @Target(AnnotationTarget.CLASS)
        annotation class InheritedTag(val value: String)

        @InheritedTag("base")
        open class Base

        class Child : Base()

        @InheritedTag("child")
        class OverrideChild : Base()

        @InheritedTag("interface")
        interface TaggedInterface

        class ImplementsTaggedInterface : TaggedInterface

        fun box(): String {
            val classToken: Class<C> = C::class.java
            if (!classToken.desiredAssertionStatus()) return "Fail Class token control"

            val b1 = B(object : A {})
            val b2 = B(object : A {})
            if (b1.hashCode() == b2.hashCode()) return "Fail 1"
            if (b1.equals(b2)) return "Fail 2"

            val anno = C::class.java.annotations.filterIsInstance<Anno>().firstOrNull()
                ?: return "Fail annotation lookup"
            val c1 = C(anno)
            val c2 = C(anno)
            if (c1.hashCode() != c2.hashCode()) return "Fail 3"
            if (!c1.equals(c2)) return "Fail 4"

            val inherited = Child::class.java.annotations.filterIsInstance<InheritedTag>().singleOrNull()
                ?: return "Fail inherited annotation"
            if (inherited.value != "base") return "Fail inherited value"
            val overridden = OverrideChild::class.java.annotations.filterIsInstance<InheritedTag>().singleOrNull()
                ?: return "Fail override annotation"
            if (overridden.value != "child") return "Fail override value"
            if (ImplementsTaggedInterface::class.java.annotations.any { it is InheritedTag }) {
                return "Fail interface inheritance"
            }

            val d1 = D<Int>(1)
            val d2 = D<Int>(2)
            if (d1.hashCode() == d2.hashCode()) return "Fail 5"
            if (d1.equals(d2)) return "Fail 6"

            return "OK"
        }

        fun main() { print(box()) }
        """
        let artifact = try Self.buildStdlibArtifact()
        let lane = try #require(OptimizationLevel(rawValue: optimization))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("typeParameterWithNonTrivialBound.kt").path
        let output = directory.appendingPathComponent("javaClassAnnotations").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)
        let options = CompilerOptions(
            moduleName: "KUU2345JavaClassAnnotations",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: lane,
            includeStdlib: fromSource,
            stdlibLibraryPath: fromSource ? nil : artifact,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stderr.isEmpty, "\(result.stderr)")
        #expect(result.stdout == "OK")
    }
}
