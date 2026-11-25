@testable import CompilerCore
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendGenericFunctionValueFieldSIGBUSRegressionTests {

    @Test
    func testCodegenGenericFunctionValueFromPairFieldStringRegression() throws {
        let source = """
        fun <T1> invokeFromPair(pair: Pair<(T1) -> Unit, T1>) {
            val f = pair.first
            f(pair.second)
        }

        fun main() {
            val block: (String) -> Unit = { p -> print("val=$p;") }
            val pair = Pair(block, "hello")
            invokeFromPair<String>(pair)
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericFunctionValuePairFieldString",
            expected: "val=hello;done\n"
        )
    }

    @Test
    func testCodegenGenericFunctionValueFromPairFieldIntRegression() throws {
        let source = """
        fun <T1> invokeFromPair(pair: Pair<(T1) -> Unit, T1>) {
            val f = pair.first
            f(pair.second)
        }

        fun main() {
            val block: (Int) -> Unit = { p -> print("val=$p;") }
            val pair = Pair(block, 42)
            invokeFromPair<Int>(pair)
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericFunctionValuePairFieldInt",
            expected: "val=42;done\n"
        )
    }

    @Test
    func testCodegenGenericFunctionValueFromTripleFieldRegression() throws {
        let source = """
        fun <T1> invokeFromTriple(t: Triple<(T1) -> Unit, T1, Int>) {
            val f = t.first
            f(t.second)
        }

        fun main() {
            val block: (String) -> Unit = { p -> print("val=$p;") }
            val t = Triple(block, "triple-hello", 7)
            invokeFromTriple<String>(t)
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericFunctionValueTripleField",
            expected: "val=triple-hello;done\n"
        )
    }

    @Test
    func testCodegenGenericFunctionValueFromUserDefinedGenericClassFieldRegression() throws {
        let source = """
        class Box<T>(val value: T)

        fun main() {
            val block: (String) -> Unit = { p -> print("val=$p;") }
            val box: Box<(String) -> Unit> = Box(block)
            val f = box.value
            f("direct-call")
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericFunctionValueUserDefinedClassField",
            expected: "val=direct-call;done\n"
        )
    }

    /// KUU-558: invariant `Box<T>` argument matching must expose type
    /// variables nested inside its function-typed `T` in both constraint
    /// directions. Keep the field read and invoke as separate expressions;
    /// direct function-property invocation is independently tracked by KUU-482.
    @Test
    func testCodegenNestedGenericFunctionTypeConstraintRegression() throws {
        let source = """
        class Box<T>(val value: T)

        fun <T1> invokeFromBox(box: Box<(T1) -> Unit>, arg: T1) {
            val function = box.value
            function(arg)
        }

        fun main() {
            val block: (String) -> Unit = { value -> print("val=$value;") }
            val box = Box<(String) -> Unit>(block)
            invokeFromBox<String>(box, "explicit")
            invokeFromBox(box, "inferred")
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NestedGenericFunctionTypeConstraint",
            expected: "val=explicit;val=inferred;done\n"
        )
    }

    @Test
    func testCodegenGenericFunctionValueFromListOfRegression() throws {
        let source = """
        fun main() {
            val block: (String) -> Unit = { p -> print("val=$p;") }
            val list = listOf(block)
            list[0]("list-hello")
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericFunctionValueListOf",
            expected: "val=list-hello;done\n"
        )
    }

    @Test
    func testCodegenGenericFunctionValueFromSetOfRegression() throws {
        let source = """
        fun main() {
            val block: (String) -> Unit = { p -> print("val=$p;") }
            val s = setOf(block)
            s.first()("set-hello")
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericFunctionValueSetOf",
            expected: "val=set-hello;done\n"
        )
    }

    @Test
    func testCodegenGenericFunctionValueFromListOfMultipleElementsRegression() throws {
        let source = """
        fun main() {
            val blockA: (String) -> Unit = { p -> print("A=$p;") }
            val blockB: (String) -> Unit = { p -> print("B=$p;") }
            val list = listOf(blockA, blockB)
            list[0]("x")
            list[1]("y")
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericFunctionValueListOfMultipleElements",
            expected: "A=x;B=y;done\n"
        )
    }

    @Test
    func testCodegenGenericFunctionValueFromArrayOfRegression() throws {
        let source = """
        fun main() {
            val block: (String) -> Unit = { p -> print("val=$p;") }
            val arr = arrayOf(block)
            arr[0]("array-hello")
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericFunctionValueArrayOf",
            expected: "val=array-hello;done\n"
        )
    }

    @Test
    func testCodegenArrayOfOrdinaryElementsRegression() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr[0] + arr[1] + arr[2])
            val strs = arrayOf("a", "b", "c")
            println(strs.joinToString(","))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayOfOrdinaryElements",
            expected: "6\na,b,c\n"
        )
    }

    @Test
    func testCodegenGenericFunctionValueFromMutableListAddRegression() throws {
        let source = """
        fun main() {
            val block: (String) -> Unit = { p -> print("val=$p;") }
            val l = mutableListOf<(String) -> Unit>()
            l.add(block)
            l[0]("mutlist-hello")
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericFunctionValueMutableListAdd",
            expected: "val=mutlist-hello;done\n"
        )
    }
}
#endif
