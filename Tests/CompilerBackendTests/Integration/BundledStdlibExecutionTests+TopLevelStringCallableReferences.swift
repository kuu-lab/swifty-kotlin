@testable import CompilerCore
import Testing

@Suite(.serialized)
struct TopLevelStringCallableReferenceExecutionTests {
    private let reducedSource = """
    class A {
        fun text(): String = "member"
        fun number(): Int = 42
    }
    fun topLevel(): String = "top"
    val globalMember: (A) -> String = A::text
    val globalTop: () -> String = ::topLevel
    val globalBound: () -> String = A()::text
    val globalNumber: (A) -> Int = A::number
    fun main() {
        print(globalMember(A())); print("|")
        print(globalTop()); print("|")
        print(globalBound()); print("|")
        print(globalNumber(A())); print("|\\n")
        val localMember: (A) -> String = A::text
        val localTop: () -> String = ::topLevel
        val localBound: () -> String = A()::text
        val localNumber: (A) -> Int = A::number
        print(localMember(A())); print("|")
        print(localTop()); print("|")
        print(localBound()); print("|")
        print(localNumber(A())); print("|\\n")
    }
    """

    private let overloadedSource = """
    fun foo(): String = "foo1"
    fun foo(i: Int): String = "foo2"
    val f1: () -> String = ::foo
    val f2: (Int) -> String = ::foo
    fun foo1() {}
    fun foo2(i: Int) {}
    fun bar(f: () -> Unit): String = "bar1"
    fun bar(f: (Int) -> Unit): String = "bar2"
    fun box(): String {
        val x1 = f1()
        if (x1 != "foo1") return "Fail 1: $x1"
        val x2 = f2(0)
        if (x2 != "foo2") return "Fail 2: $x2"
        val y1 = bar(::foo1)
        if (y1 != "bar1") return "Fail 3: $y1"
        val y2 = bar(::foo2)
        if (y2 != "bar2") return "Fail 4: $y2"
        return "OK"
    }
    fun main() { print(box()) }
    """

    @Test
    func reducedReproMatchesKotlinWithSourceStdlibO0() throws {
        try runReducedRepro(allowDefaultStdlibLibrary: false, optLevel: .O0)
    }

    @Test
    func reducedReproMatchesKotlinWithFreshStdlibArtifactO0() throws {
        try runReducedRepro(allowDefaultStdlibLibrary: true, optLevel: .O0)
    }

    @Test
    func reducedReproMatchesKotlinWithFreshStdlibArtifactO2() throws {
        try runReducedRepro(allowDefaultStdlibLibrary: true, optLevel: .O2)
    }

    @Test
    func overloadedOriginalMatchesKotlinWithSourceStdlibO0() throws {
        try runOverloadedOriginal(allowDefaultStdlibLibrary: false, optLevel: .O0)
    }

    @Test
    func overloadedOriginalMatchesKotlinWithFreshStdlibArtifactO0() throws {
        try runOverloadedOriginal(allowDefaultStdlibLibrary: true, optLevel: .O0)
    }

    @Test
    func overloadedOriginalMatchesKotlinWithFreshStdlibArtifactO2() throws {
        try runOverloadedOriginal(allowDefaultStdlibLibrary: true, optLevel: .O2)
    }

    // Source-injected O2 fails LLVM verification for a plain hello fixture too
    // (KUU-2241), so this suite covers O2 through the fresh stdlib artifact.
    private func runReducedRepro(
        allowDefaultStdlibLibrary: Bool,
        optLevel: OptimizationLevel
    ) throws {
        try compileAndRunKotlin(
            reducedSource,
            expectedOutput: "member|top|member|42|\nmember|top|member|42|\n",
            moduleName: "KUU2319MinimalTopLevelStringCallableReferences",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optLevel
        )
    }

    private func runOverloadedOriginal(
        allowDefaultStdlibLibrary: Bool,
        optLevel: OptimizationLevel
    ) throws {
        try compileAndRunKotlin(
            overloadedSource,
            expectedOutput: "OK",
            moduleName: "KUU2319OverloadedTopLevelStringCallableReferences",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optLevel
        )
    }
}
