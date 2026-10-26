@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CovariantPairLUBTests {
    private let declarations = """
        open class Module
        class A: Module()
        class B: Module()
        class Other
        class Pair<out F, out S>(val first: F, val second: S)
        """

    @Test
    func infersCommonParentWithoutExpectedReturnType() throws {
        let source = declarations + """

            fun choose(flag: Boolean) = if (flag) Pair("x", A()) else Pair("x", B())
            fun probe(flag: Boolean): Pair<String, Module> = choose(flag)
            fun reversed(flag: Boolean) = if (flag) Pair("x", B()) else Pair("x", A())
            fun probeReversed(flag: Boolean): Pair<String, Module> = reversed(flag)
            fun nullable(flag: Boolean, a: A?) = if (flag) Pair("x", a) else Pair("x", B())
            fun probeNullable(flag: Boolean, a: A?): Pair<String, Module?> = nullable(flag, a)
            fun unrelated(flag: Boolean) = if (flag) Pair("x", A()) else Pair("x", Other())
            fun probeUnrelated(flag: Boolean): Pair<String, Any> = unrelated(flag)
            open class Base<out T>(val value: T)
            class Left<T>(value: T): Base<T>(value)
            class Right<T>(value: T): Base<T>(value)
            fun inherited(flag: Boolean) = if (flag) Left(A()) else Right(B())
            fun probeInherited(flag: Boolean): Base<Module> = inherited(flag)
            """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [
        "fun choose(flag: Boolean) = if (flag) Pair(\"x\", A()) else Pair(\"x\", B())\nfun bad(flag: Boolean): Pair<String, A> = choose(flag)",
        "fun choose(flag: Boolean) = if (flag) Pair(\"x\", A()) else Pair(\"x\", Other())\nfun bad(flag: Boolean): Pair<String, Module> = choose(flag)",
        "fun choose(flag: Boolean, a: A?) = if (flag) Pair(\"x\", a) else Pair(\"x\", B())\nfun bad(flag: Boolean, a: A?): Pair<String, Module> = choose(flag, a)",
        "class Box<T>(val value: T)\nfun choose(flag: Boolean) = if (flag) Box(A()) else Box(B())\nfun bad(flag: Boolean): Box<Module> = choose(flag)",
        "class Sink<in T>\nfun choose(flag: Boolean) = if (flag) Sink<A>() else Sink<B>()\nfun bad(flag: Boolean): Sink<Module> = choose(flag)",
    ])
    func rejectsNarrowerOrIncompatibleResults(probe: String) throws {
        try withTemporaryFile(contents: declarations + "\n" + probe) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
        }
    }
}
