#if canImport(Testing)
// BUG-264: End-to-end execution tests for *named* object declarations
// (`object Named : Base(args) { ... }`) that inherit an open *class*.
// KSP-CAP-018 fixed the same shape for anonymous object expressions
// (`object : Base(x) { ... }`), but named object declarations were out of
// its scope: `synthesizeObjectInitializer` ran property initializers and
// init blocks yet never emitted the superclass constructor call, so the
// arguments were silently discarded and every inherited property kept its
// zeroed default (printing `0` instead of `7` for `object Named : Base2(7)`).
// The same gap also meant a `Base()` superclass's own property initializers
// and init blocks never ran at all. Nested objects with only a class
// superclass additionally never got an initializer at all (the nested-object
// gate only looked for interface supertypes), so reads of inherited members
// panicked at runtime.
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendNamedObjectSuperConstructorTests {

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: moduleName,
                inputs: [path],
                outputPath: outputBase,
                emit: .executable,
                target: defaultTargetTriple()
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testNamedObjectRunsSuperclassConstructorWithArguments() throws {
        let source = """
        open class Base2(val v: Int)
        object Named : Base2(7)
        fun main() { println(Named.v) }
        """
        try assertKotlinOutput(source, moduleName: "NamedObjectSuperCtorArgs", expected: "7\n")
    }

    @Test
    func testNamedObjectRunsInheritedPropertyInitializerWithoutArguments() throws {
        let source = """
        open class Fixed {
            val answer: Int = 42
            open fun describe(): String = "Fixed(" + answer + ")"
        }
        object Named : Fixed()
        fun main() {
            println(Named.answer)
            println(Named.describe())
        }
        """
        try assertKotlinOutput(
            source, moduleName: "NamedObjectNoCtorArgs", expected: "42\nFixed(42)\n"
        )
    }

    @Test
    func testNamedObjectSuperConstructorResolvesMatchingOverload() throws {
        let source = """
        open class Multi {
            val label: String
            constructor(v: Int) { label = "int:" + v }
            constructor(s: String) { label = "str:" + s }
        }
        object FromInt : Multi(7)
        object FromString : Multi("hi")
        fun main() {
            println(FromInt.label)
            println(FromString.label)
        }
        """
        try assertKotlinOutput(
            source, moduleName: "NamedObjectSuperCtorOverload", expected: "int:7\nstr:hi\n"
        )
    }

    @Test
    func testNamedObjectSuperConstructorArgumentReadsTopLevelProperty() throws {
        let source = """
        open class Seed(val s: Int)
        val seed = 40
        object Named : Seed(seed + 2)
        fun main() { println(Named.s) }
        """
        try assertKotlinOutput(
            source, moduleName: "NamedObjectTopLevelArg", expected: "42\n"
        )
    }

    @Test
    func testNamedObjectSuperConstructorRunsBeforeOwnInitializers() throws {
        let source = """
        open class Step(val step: Int)
        object Named : Step(3) {
            val own: Int = step * 10
        }
        fun main() { println(Named.own) }
        """
        try assertKotlinOutput(
            source, moduleName: "NamedObjectInitOrder", expected: "30\n"
        )
    }

    @Test
    func testNamedObjectOverrideDispatchesThroughBaseTypedStaticType() throws {
        let source = """
        open class Base3 { open fun describe(): String = "base" }
        object Named2 : Base3() { override fun describe(): String = "named" }
        fun main() {
            val b: Base3 = Named2
            println(b.describe())
        }
        """
        try assertKotlinOutput(
            source, moduleName: "NamedObjectOverrideDispatch", expected: "named\n"
        )
    }

    @Test
    func testNestedObjectRunsSuperclassConstructorWithArguments() throws {
        let source = """
        open class Base2(val v: Int)
        class Outer { object N : Base2(9) }
        fun main() {
            println(Outer.N.v)
            println(Outer.N is Base2)
        }
        """
        try assertKotlinOutput(
            source, moduleName: "NestedObjectSuperCtorArgs", expected: "9\ntrue\n"
        )
    }

    @Test
    func testNestedObjectWithInterfaceRunsSuperclassConstructor() throws {
        let source = """
        open class Base2(val v: Int)
        interface Iface { fun tag(): String }
        class Outer {
            object M : Base2(5), Iface { override fun tag(): String = "M" }
        }
        fun main() {
            println(Outer.M.v)
            println(Outer.M.tag())
            println(Outer.M is Iface)
        }
        """
        try assertKotlinOutput(
            source, moduleName: "NestedObjectIfaceSuperCtor", expected: "5\nM\ntrue\n"
        )
    }
}
#endif
