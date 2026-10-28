#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendDefaultParameterValuesTests {

    @Test func testTopLevelFunctionDefaultValueConstructsClassInstance() throws {
        let source = """
        class Simple(val n: Int = 9)
        fun foo(x: Simple = Simple()): Int = x.n
        fun main() {
            println(foo())
        }
        """
        try assertKotlinOutput(source, moduleName: "DefaultValueConstructorCall", expected: "9\n")
    }

    @Test func testTopLevelFunctionDefaultValueReadsCompanionProperty() throws {
        let source = """
        class Bar(val tag: String) {
            companion object {
                val Def: Bar = Bar("default")
            }
        }
        fun greet(b: Bar = Bar.Def): String = b.tag
        fun main() {
            println(greet())
        }
        """
        try assertKotlinOutput(source, moduleName: "DefaultValueCompanionPropertyRead", expected: "default\n")
    }

    @Test func testMemberFunctionDefaultValueConstructsClassInstance() throws {
        let source = """
        class Simple(val n: Int = 9)
        class Holder {
            fun foo(x: Simple = Simple()): Int = x.n
        }
        fun main() {
            println(Holder().foo())
        }
        """
        try assertKotlinOutput(source, moduleName: "MemberDefaultValueConstructorCall", expected: "9\n")
    }

    @Test func testPrimaryConstructorDefaultValueConstructsClassInstance() throws {
        let source = """
        class Simple(val n: Int = 9)
        class Holder(val payload: Simple = Simple())
        fun main() {
            println(Holder().payload.n)
        }
        """
        try assertKotlinOutput(source, moduleName: "PrimaryCtorDefaultValueConstructorCall", expected: "9\n")
    }

    @Test func testSecondaryConstructorDefaultValueConstructsClassInstance() throws {
        let source = """
        class Simple(val n: Int = 9)
        class Holder {
            val payload: Simple
            constructor(x: Simple = Simple()) {
                payload = x
            }
        }
        fun main() {
            println(Holder().payload.n)
        }
        """
        try assertKotlinOutput(source, moduleName: "SecondaryCtorDefaultValueConstructorCall", expected: "9\n")
    }

    @Test(arguments: [0, 2])
    func testSecondaryConstructorDefaultWithThisDelegationInObjectSuperCall(optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let source = """
        open class Foo(val args: String) {
            constructor(arg: Any = 1) : this(arg.toString())
        }
        object TF : Foo() {}
        fun box() = object : Foo() {}.args
        fun main() { println(box()) }
        """
        try assertKotlinOutput(
            source,
            moduleName: "SecondaryCtorDefaultThisDelegationObjectSuperCall",
            expected: "1\n",
            optLevel: optLevel
        )
    }

    @Test func testDefaultValueExpressionMayReferenceEarlierParameter() throws {
        let source = """
        fun foo(a: Int, b: Int = a + 1): Int = a + b
        fun main() {
            println(foo(10))
        }
        """
        try assertKotlinOutput(source, moduleName: "DefaultValueReferencesEarlierParameter", expected: "21\n")
    }
}
#endif
