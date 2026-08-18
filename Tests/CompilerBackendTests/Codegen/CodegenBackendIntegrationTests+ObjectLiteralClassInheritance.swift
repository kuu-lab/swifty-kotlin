#if canImport(Testing)
// KSP-CAP-018: End-to-end execution tests for object-expression literals
// (`object : Base(args) { override fun ... }`) that inherit an open *class*
// (as opposed to an interface, already covered by BUG-141/KSP-CAP-001).
//
// Four independent bugs made this shape unusable before this fix:
// (1) An object literal's own `override` members were never assigned a
//     vtable slot — `ExprTypeChecker+ObjectLiteralInference.swift` copied the
//     superclass's `vtableSlots` verbatim instead of re-running override
//     resolution, since object literals are processed during body analysis,
//     after `LayoutSynthesis.synthesizeNominalLayouts` has already run for
//     every named nominal. A call through the base-typed static type kept
//     dispatching to the base class's own implementation.
// (2) The superclass constructor invocation's arguments
//     (`object : Base(x) { ... }`) were discarded entirely at parse time
//     (`parseObjectLiteral` used to just skip the balanced parens), and the
//     compiler never called the superclass constructor for an object literal
//     at all — so inherited properties kept their zeroed defaults, mirroring
//     BUG-155/PR #5506 for named classes.
// (3) `parseTail`'s newline-continuation heuristic (`KotlinParser+Statements.swift`)
//     treated a bare `object` keyword after a newline as always starting a new
//     top-level declaration, so an expression-bodied function whose object
//     literal body starts on the *next* line (upstream kotlin-stdlib's actual
//     formatting style for e.g. `Delegates.observable`) failed to parse at
//     all. Fixed by having the two boundary checks in `parseTail` look one
//     token further ahead: `object` immediately followed by `:` or `{` (no
//     name) is an expression continuing the statement, not a new declaration.
// (4) The superclass constructor call picked the *first* `<init>` overload
//     found (`lookupAll(...).first`) regardless of whether its parameters
//     actually matched the object literal's arguments, so a superclass with
//     multiple constructors could silently run the wrong one.
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendObjectLiteralClassInheritanceTests {

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
    func testObjectLiteralOverrideDispatchesThroughBaseTypedStaticType() throws {
        let source = """
        open class Base { open fun describe(): String = "base" }
        fun make(): Base = object : Base() { override fun describe(): String = "anon" }
        fun main() { println(make().describe()) }
        """
        try assertKotlinOutput(source, moduleName: "ObjectLiteralOverrideDispatch", expected: "anon\n")
    }

    @Test
    func testObjectLiteralRunsSuperclassConstructorWithArguments() throws {
        let source = """
        open class Vehicle(val name: String) {
            open fun describe(): String = "Vehicle($name)"
        }
        fun makeVehicle(name: String): Vehicle = object : Vehicle(name) {
            override fun describe(): String = "Custom($name)"
        }
        fun main() {
            val vehicle = makeVehicle("car")
            println(vehicle.name)
            println(vehicle.describe())
        }
        """
        try assertKotlinOutput(source, moduleName: "ObjectLiteralSuperCtorArgs", expected: "car\nCustom(car)\n")
    }

    @Test
    func testObjectLiteralSuperclassConstructorArgumentResolvesGenericOuterParameter() throws {
        let source = """
        open class Box<V>(val value: V) {
            open fun render(): String = "Box($value)"
        }
        fun <T> makeBox(value: T, onRender: (T) -> String): Box<T> = object : Box<T>(value) {
            override fun render(): String = onRender(value)
        }
        fun main() {
            val box = makeBox(42) { v -> "Rendered($v)" }
            println(box.value)
            println(box.render())
        }
        """
        try assertKotlinOutput(source, moduleName: "ObjectLiteralGenericSuperCtorArg", expected: "42\nRendered(42)\n")
    }

    @Test
    func testObjectLiteralBodyStartingOnNextLineAfterEqualsParses() throws {
        let source = """
        open class Base { open fun describe(): String = "base" }
        fun make(): Base =
            object : Base() {
                override fun describe(): String = "anon"
            }
        fun main() { println(make().describe()) }
        """
        try assertKotlinOutput(source, moduleName: "ObjectLiteralMultilineBody", expected: "anon\n")
    }

    @Test
    func testObjectLiteralSuperConstructorResolvesMatchingOverload() throws {
        let source = """
        open class Multi {
            val label: String
            constructor(v: Int) { label = "int:" + v }
            constructor(s: String) { label = "str:" + s }
            open fun describe(): String = "base:" + label
        }
        fun makeFromInt(v: Int): Multi = object : Multi(v) {
            override fun describe(): String = "over:" + label
        }
        fun makeFromString(s: String): Multi = object : Multi(s) {
            override fun describe(): String = "over:" + label
        }
        fun main() {
            println(makeFromInt(7).describe())
            println(makeFromString("hi").describe())
        }
        """
        try assertKotlinOutput(
            source, moduleName: "ObjectLiteralSuperCtorOverload", expected: "over:int:7\nover:str:hi\n"
        )
    }
}
#endif
