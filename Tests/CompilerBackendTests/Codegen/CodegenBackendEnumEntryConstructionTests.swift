#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// Pinned from JetBrains Kotlin at 679366a83f99851b42f64795f10ed803ff011c73.
private let publishedSecondaryConstructorsEnumFixture = """
enum class A1(val prop1: String) {
    X("asd"),
    Y() {
        override fun f() = super.f() + "#Y"
    },
    Z(5);

    val prop2: String = "const2"
    var prop3: String = ""

    constructor(): this("default") {
        prop3 = "empty"
    }
    constructor(x: Int): this(x.toString()) {
        prop3 = "int"
    }

    open fun f(): String = "$prop1#$prop2#$prop3"
}

enum class A2 {
    X("asd"),
    Y() {
        override fun f() = super.f() + "#Y"
    },
    Z(5);
    val prop1: String
    val prop2: String = "const2"
    var prop3: String = ""

    constructor(arg: String) {
        prop1 = arg
    }
    constructor() {
        prop1 = "default"
        prop3 = "empty"
    }
    constructor(x: Int): this(x.toString()) {
        prop3 = "int"
    }

    open fun f(): String = "$prop1#$prop2#$prop3"
}
fun box(): String {
    val a1x = A1.X
    if (a1x.f() != "asd#const2#") return "fail1: ${a1x.f()}"
    val a1y = A1.Y
    if (a1y.f() != "default#const2#empty#Y") return "fail2: ${a1y.f()}"
    val a1z = A1.Z
    if (a1z.f() != "5#const2#int") return "fail3: ${a1z.f()}"
    val a2x = A2.X
    if (a2x.f() != "asd#const2#") return "fail4: ${a2x.f()}"
    val a2y = A2.Y
    if (a2y.f() != "default#const2#empty#Y") return "fail5: ${a2y.f()}"
    val a2z = A2.Z
    if (a2z.f() != "5#const2#int") return "fail6: ${a2z.f()}"

    return "OK"
}
"""

/// Enum entries are constructed once, lazily on first access to the enum
/// class: constructor arguments are evaluated a single time (bound by label,
/// with defaults that see earlier parameters), and the class body's property
/// initializers and `init` blocks plus entry-body properties run once per
/// entry. Values live in per-entry storage behind the enum property helpers
/// (`KIRLoweringDriver+EnumEntryStorage.swift`).
@Suite
struct CodegenBackendEnumEntryConstructionTests {

    @Test
    func testConstructorArgumentsAreEvaluatedOnce() throws {
        let source = """
        var counter = 0
        fun next(): Int { counter++; return counter }
        enum class E(val id: Int) { A(next()), B(next()) }

        fun main() {
            println(counter)
            println(E.A.id)
            println(E.A.id)
            println(E.B.id)
            println(counter)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumCtorArgsOnce",
            expected: "0\n1\n1\n2\n2\n"
        )
    }

    @Test
    func testSecondaryConstructorSelectionAndBodies() throws {
        let source = """
        enum class E(val label: String, val code: Int) {
            PRIMARY("primary", 0),
            NAMED(code = 5, label = "named"),
            EMPTY(),
            NUMBER(7),
            DEFAULTED(marker = "named-default"),
            BOOLEAN(true);

            var trace = "primary"

            constructor() : this("empty", 1) { trace = "noarg" }
            constructor(value: Int) : this(value.toString(), value) { trace = "int" }
            constructor(flag: Boolean = false, marker: String = "default") :
                this(marker, if (flag) 2 else 3) {
                trace = if (flag) "boolean-true" else "boolean-default"
            }
        }

        fun main() {
            println("${E.PRIMARY.label}:${E.PRIMARY.trace}")
            println("${E.NAMED.label}:${E.NAMED.trace}")
            println("${E.EMPTY.label}:${E.EMPTY.trace}")
            println("${E.NUMBER.label}:${E.NUMBER.trace}")
            println("${E.DEFAULTED.label}:${E.DEFAULTED.trace}")
            println("${E.BOOLEAN.label}:${E.BOOLEAN.trace}")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumSecondaryConstructorSelection",
            expected: "primary:primary\nnamed:primary\nempty:noarg\n7:int\nnamed-default:boolean-default\ndefault:boolean-true\n"
        )
    }

    /// Source-backed O2 is blocked by the independent FunctionN verifier issue KUU-2241.
    @Test
    func testPublishedFixtureAndControlsAcrossStdlibModes() throws {
        let source = publishedSecondaryConstructorsEnumFixture + """

        enum class MinimalEnum(val value: String) {
            A("a"), B();
            constructor() : this("b")
        }

        enum class PrimaryOnly(val value: Int) { A(1), B(2) }

        class OrdinarySecondary(val value: String) {
            constructor() : this("secondary")
        }

        fun main() {
            if (box() == "OK"
                && MinimalEnum.B.value == "b"
                && PrimaryOnly.A.value == 1
                && PrimaryOnly.B.value == 2
                && OrdinarySecondary().value == "secondary") {
                print("OK")
            } else {
                print("FAIL")
            }
        }
        """

        let configurations: [(useStdlibArtifact: Bool, optimization: Int)] = [
            (useStdlibArtifact: true, optimization: 0),
            (useStdlibArtifact: true, optimization: 2),
            (useStdlibArtifact: false, optimization: 0),
        ]
        for (useStdlibArtifact, optimization) in configurations {
            let level = try #require(OptimizationLevel(rawValue: optimization))
            let stdlibArtifact = useStdlibArtifact ? try testStdlibArtifactPath() : nil
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let inputPath = directory.appendingPathComponent("fixture.kt").path
            let outputPath = directory.appendingPathComponent("fixture").path
            try source.write(toFile: inputPath, atomically: true, encoding: .utf8)

            let options = CompilerOptions(
                moduleName: "EnumSecondaryConstructors_\(useStdlibArtifact)_O\(optimization)",
                inputs: [inputPath],
                outputPath: outputPath,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: level,
                stdlibLibraryPath: stdlibArtifact,
                allowDefaultStdlibLibrary: useStdlibArtifact
            )
            let compilation = makeTestDriver().runForTesting(options: options)
            try assertCompilationSucceeded(
                compilation,
                context: "KUU-2287 source mode=\(useStdlibArtifact), O\(optimization)"
            )

            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "OK")
        }
    }

    @Test
    func testNamedArgumentsAndDefaultsReferringToEarlierParameters() throws {
        let source = """
        enum class C(val r: Int, val g: Int, val b: Int = r + 1) { X(g = 1, r = 2), Y(5, 6) }

        fun main() {
            println("${C.X.r} ${C.X.g} ${C.X.b}")
            println("${C.Y.r} ${C.Y.g} ${C.Y.b}")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumNamedArgsDefault",
            expected: "2 1 3\n5 6 6\n"
        )
    }

    /// `init` after the entry list's `;` was parsed as a third enum entry, so
    /// the block never ran (and `values()` grew a bogus `init` entry).
    @Test
    func testInitBlocksRunOnFirstAccess() throws {
        let source = """
        enum class E { A, B; init { println("init " + name) } }

        fun main() {
            println("start")
            println(E.A)
            println(E.values().size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumInitBlock",
            expected: "start\ninit A\ninit B\nA\n2\n"
        )
    }

    @Test
    func testBodyPropertiesAreStoredPerEntry() throws {
        let source = """
        enum class E(val n: Int) {
            A(3), B(4);
            val sq = n * n
            var hits = 0
            val tag: String
            init { tag = name + sq }
            fun bump() { hits += 10 }
        }

        fun main() {
            E.A.hits++
            E.A.bump()
            E.B.hits = 5
            println(E.A.sq)
            println(E.B.sq)
            println(E.A.hits)
            println(E.B.hits)
            println(E.B.tag)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumBodyProperties",
            expected: "9\n16\n11\n5\nB16\n"
        )
    }

    @Test
    func testEntryBodyOverrideVal() throws {
        let source = """
        enum class Op {
            PLUS { override val sym = "+" },
            MINUS { override val sym = "-" };
            abstract val sym: String
        }

        fun main() {
            println(Op.PLUS.sym + Op.MINUS.sym)
            for (op in Op.entries) println(op.sym)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumEntryOverrideVal",
            expected: "+-\n+\n-\n"
        )
    }

    @Test
    func testEntryBodyStoredPropertiesAreReadableFromOverrides() throws {
        let source = """
        enum class Direction() {
            NORTH {
                val someSpecialValue = "OK"
                override fun f() = someSpecialValue
            },
            SOUTH { override fun f() = "LITERAL" };
            val bodyValue = "CLASS"
            fun readBodyValue() = bodyValue
            abstract fun f(): String
        }

        enum class X {
            B {
                val value2 = "OK"
                override val value = { value2 }
            };
            abstract val value: () -> String
        }

        fun main() {
            println(Direction.NORTH.f())
            println(Direction.SOUTH.f())
            println(Direction.NORTH.readBodyValue())
            println(X.B.value())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumEntryBodyPropertyOverride",
            expected: "OK\nLITERAL\nCLASS\nOK\n"
        )
    }

    /// The itable getter registered for an interface property overridden by
    /// an enum constructor property used to read an instance field offset
    /// from the ordinal box and trip `kk_array_get_inbounds`.
    @Test
    func testInterfacePropertyOverriddenByConstructorPropertyThroughInterface() throws {
        let source = """
        interface HasCode { val code: Int }
        enum class St(override val code: Int) : HasCode { OK(200), NF(404) }

        fun main() {
            val h: HasCode = St.NF
            println(h.code)
            println(St.OK.code)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumInterfacePropertyOverride",
            expected: "404\n200\n"
        )
    }
}
#endif
