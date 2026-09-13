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
// (5) `superTypeConstructorArgs` was invisible to both capture-analysis
//     traversals (Sema `CaptureAnalyzer` and KIR `LambdaLowerer+
//     CaptureAnalysis`), which only walked an object literal's member bodies
//     and property initializers. When the object literal sat inside a
//     lambda and an outer local was referenced only from its superclass
//     constructor call, the local was never added to the lambda's capture
//     list even though the lowered body still referenced it.
// (6) `parseBlock`'s block-start declaration dispatch had the same "bare
//     `object` keyword always starts a declaration" bug as (3), but for a
//     block/lambda body's *first* statement rather than a top-level
//     expression-bodied function: a lambda whose entire body was the bare
//     object literal expression (`{ object : Base(x) { ... } }`) mis-parsed
//     `object` as a new named declaration.
// (9) A property's custom accessors were invisible to Sema:
//     `ensureObjectLiteralSymbol` walked only `propertyDecl.initializer`, so
//     identifiers in a getter/setter body got no `identifierSymbols` binding
//     and KIR lowered them to `.unit`. Fixing that alone was not enough --
//     four more layers had to move: accessor bodies needed the enclosing
//     `locals` seeded (`baseLocals`, as member function bodies already get);
//     the implicit-receiver read path loaded a computed property's
//     never-written instance slot instead of calling its accessor (which is
//     why reading through a member returned 0 while the explicit-receiver read
//     already called `get`); a property with accessors *and* storage needed a
//     `$backing_` symbol so `field` stopped resolving back to the property
//     itself and making the accessor recurse into itself; and the lambda
//     capture traversals had to walk accessor bodies so an outer local used
//     only there reaches the closure that constructs the literal.
// (8) `parseObjectLiteralFunctionDecl`/`parseObjectLiteralPropertyDecl` re-parse
//     a member's tokens with a fresh `KotlinParser`, and stripped *every*
//     semicolon first to drop the separator between members. That also removed
//     the statement separators inside the member's own body, so a single-line
//     multi-statement body (`fun bump(): Int { i = i + 1; return i }`)
//     re-parsed as one malformed statement and failed with
//     `KSWIFTK-TYPE-0001: Type constraint could not be satisfied` -- valid
//     Kotlin rejected, with a diagnostic pointing nowhere near the cause. The
//     same line formatted across two lines compiled fine.
// (7) An object literal declaring *no* members (`object : Base(x) {}`) got no
//     `ObjectDecl` at all -- `parseObjectLiteralDecl` returned `nil` for an
//     empty body -- so it took `ObjectLiteralLowerer`'s no-decl path, which
//     allocates via `kk_object_new` with `classID = 0` and no `NominalLayout`,
//     registers no supertype edges, and emits no superclass constructor call.
//     Inherited fields therefore had no slots reserved and their initializers
//     never ran, so reading any inherited property panicked with
//     `kk_array_get_inbounds precondition failed`. Note this was *not* limited
//     to headers with constructor arguments: `object : Base() {}` over a base
//     with an initialized property crashed the same way.
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

    @Test
    func testObjectLiteralInsideLambdaCapturesOuterLocalUsedOnlyInSuperCtorArgs() throws {
        let source = """
        open class Base(val v: Int) { open fun f(): String = "base:" + v }
        fun make(x: Int): () -> Base = { object : Base(x) { override fun f(): String = "anon:" + v } }
        fun main() {
            val factory = make(42)
            val obj = factory()
            println(obj.v)
            println(obj.f())
        }
        """
        try assertKotlinOutput(source, moduleName: "ObjectLiteralLambdaSuperCtorCapture", expected: "42\nanon:42\n")
    }

    @Test
    func testObjectLiteralAsBareLambdaBodyDispatchesOverride() throws {
        let source = """
        open class Base { open fun f(): String = "base" }
        fun make(): () -> Base = { object : Base() { override fun f(): String = "anon" } }
        fun main() { println(make()().f()) }
        """
        try assertKotlinOutput(source, moduleName: "ObjectLiteralBareLambdaBody", expected: "anon\n")
    }

    @Test
    func testEmptyBodyObjectLiteralRunsSuperclassConstructorWithArguments() throws {
        let source = """
        open class Base2(val v: Int)
        fun make2(x: Int): Base2 = object : Base2(x) {}
        fun main() { println(make2(7).v) }
        """
        try assertKotlinOutput(source, moduleName: "EmptyObjectLiteralSuperCtorArgs", expected: "7\n")
    }

    @Test
    func testEmptyBodyObjectLiteralRunsInheritedPropertyInitializerWithoutArguments() throws {
        let source = """
        open class Fixed {
            val answer: Int = 42
            open fun describe(): String = "Fixed(" + answer + ")"
        }
        fun makeFixed(): Fixed = object : Fixed() {}
        fun main() {
            val fixed = makeFixed()
            println(fixed.answer)
            println(fixed.describe())
        }
        """
        try assertKotlinOutput(
            source, moduleName: "EmptyObjectLiteralNoCtorArgs", expected: "42\nFixed(42)\n"
        )
    }

    @Test
    func testEmptyBodyObjectLiteralInsideLambdaCapturesOuterLocalUsedOnlyInSuperCtorArgs() throws {
        let source = """
        open class Counter(val start: Int) { val doubled: Int = start * 2 }
        fun makeLater(start: Int): () -> Counter = { object : Counter(start) {} }
        fun main() {
            val counter = makeLater(11)()
            println(counter.start)
            println(counter.doubled)
        }
        """
        try assertKotlinOutput(
            source, moduleName: "EmptyObjectLiteralLambdaCapture", expected: "11\n22\n"
        )
    }

    @Test
    func testEmptyBodyObjectLiteralRegistersInterfaceAndGenericClassSupertypes() throws {
        let source = """
        interface Tagged
        open class Counter(val start: Int) { open fun describe(): String = "Counter(" + start + ")" }
        open class Holder<V>(val item: V)
        fun makeTagged(): Tagged = object : Tagged {}
        fun makeHolder(v: Int): Holder<Int> = object : Holder<Int>(v) {}
        fun makeBoth(n: Int): Counter = object : Counter(n), Tagged {}
        fun main() {
            val anyTagged: Any = makeTagged()
            println(anyTagged is Tagged)
            println(makeHolder(8).item)
            val both = makeBoth(3)
            println(both.describe())
            println(both is Tagged)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "EmptyObjectLiteralSupertypeRegistration",
            expected: "true\n8\nCounter(3)\ntrue\n"
        )
    }

    @Test
    func testObjectLiteralMemberBodyKeepsSingleLineSemicolonSeparatedStatements() throws {
        let source = """
        fun mk(): Iterator<Int> = object : Iterator<Int> {
            var i = 0
            override fun hasNext(): Boolean = i < 3
            override fun next(): Int { i = i + 1; return i }
        }
        fun main() {
            val it = mk()
            while (it.hasNext()) { println(it.next()) }
        }
        """
        try assertKotlinOutput(
            source, moduleName: "ObjectLiteralSemicolonBody", expected: "1\n2\n3\n"
        )
    }

    @Test
    func testObjectLiteralInitializerLambdaKeepsNestedSemicolons() throws {
        let source = """
        open class Base { open fun r(): String = "base" }
        fun mk(): Base = object : Base() {
            val viaLambda: Int = run { val a = 1; a + 41 }
            fun computed(): Int { val b = 2; return b * 21 }
            override fun r(): String = "" + viaLambda + "/" + computed()
        }
        fun main() { println(mk().r()) }
        """
        try assertKotlinOutput(
            source, moduleName: "ObjectLiteralNestedSemicolons", expected: "42/42\n"
        )
    }

    @Test
    func testObjectLiteralCustomGetterReadsSiblingAndInheritedProperties() throws {
        let source = """
        open class Ticker(val step: Int) { open fun r(): String = "base" }
        fun mk(s: Int): Ticker = object : Ticker(s) {
            val seed: Int = 7
            val fromSibling: Int get() = seed + 1
            val fromInherited: Int get() = step * 2
            override fun r(): String = "" + fromSibling + "/" + fromInherited
        }
        fun main() {
            println(mk(4).r())
            val direct = object : Ticker(4) { val doubled: Int get() = step * 2 }
            println(direct.doubled)
        }
        """
        try assertKotlinOutput(
            source, moduleName: "ObjectLiteralGetterSiblingInherited", expected: "8/8\n8\n"
        )
    }

    @Test
    func testObjectLiteralCustomSetterRunsThroughSeparateAndFieldBackedStorage() throws {
        let source = """
        open class B { open fun r(): String = "base" }
        fun mk(): B = object : B() {
            var backing: Int = 0
            var viaSetter: Int
                get() = backing * 10
                set(v) { backing = v + 1 }
            var viaField: Int = 0
                get() = field * 100
                set(v) { field = v + 2 }
            override fun r(): String {
                viaSetter = 3
                viaField = 1
                return "" + viaSetter + "/" + viaField
            }
        }
        fun main() { println(mk().r()) }
        """
        try assertKotlinOutput(
            source, moduleName: "ObjectLiteralCustomSetter", expected: "40/300\n"
        )
    }

    @Test
    func testObjectLiteralAccessorBodyCapturesOuterLocal() throws {
        let source = """
        open class B { open fun r(): String = "base" }
        fun make(x: Int): B = object : B() {
            val tripled: Int get() = x * 3
            override fun r(): String = "" + tripled
        }
        fun makeLater(x: Int): () -> B = { object : B() {
            val tripled: Int get() = x * 3
            override fun r(): String = "" + tripled
        } }
        fun main() {
            println(make(5).r())
            println(makeLater(6)().r())
            val local = 7
            val direct = object { val tripled: Int get() = local * 3 }
            println(direct.tripled)
        }
        """
        try assertKotlinOutput(
            source, moduleName: "ObjectLiteralAccessorCapture", expected: "15\n18\n21\n"
        )
    }
}
#endif
