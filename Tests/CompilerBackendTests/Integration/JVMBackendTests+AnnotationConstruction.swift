#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func annotationConstructorsMaterializeInterfacesAndDefaults(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            import kotlin.OverloadResolutionByLambdaReturnType
            import kotlin.experimental.ExperimentalTypeInference
            annotation class Label(val text: String = "default", val count: Int = 3)
            annotation class Values(val values: IntArray)
            var events: String = ""
            fun text(): String { events += "text;"; return "named" }
            fun count(): Int { events += "count;"; return 7 }
            @OptIn(ExperimentalTypeInference::class)
            fun main() {
                val marker = OverloadResolutionByLambdaReturnType()
                println(marker is OverloadResolutionByLambdaReturnType)
                println(marker == OverloadResolutionByLambdaReturnType())
                val defaults = Label()
                println(defaults.text); println(defaults.count)
                val named = Label(count = count(), text = text())
                println(events); println(named.text); println(named.count)
                println(defaults == Label("default", 3))
                val array = Values(intArrayOf(1, 2))
                println(array.values[1]); println(array == Values(intArrayOf(1, 2)))
            }
            """, expected: "true\ntrue\ndefault\n3\ncount;text;\nnamed\n7\ntrue\n2\ntrue\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func annotationConstructorsAdaptClassArraysWithoutChangingOtherArrays(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            import kotlin.reflect.KClass
            annotation class Classes(val types: Array<KClass<*>> = [Int::class], val scalar: KClass<*> = String::class, val names: Array<String> = ["default"])
            fun main() {
                val explicit = Classes(arrayOf(String::class, Int::class), scalar = Int::class, names = arrayOf("left", "right"))
                println(explicit.types[0].simpleName); println(explicit.types[1].simpleName)
                println(explicit.scalar.simpleName)
                println(Classes(emptyArray<KClass<*>>()).types.size)
                val defaults = Classes()
                println(defaults.types[0].simpleName); println(defaults.scalar.simpleName)
                println(defaults.names[0]); println(explicit.names[1])
                val copy = Classes(arrayOf(String::class, Int::class), scalar = Int::class, names = arrayOf("left", "right"))
                println(explicit == copy); println((explicit as Any).hashCode() == (copy as Any).hashCode())
            }
            """, expected: "String\nInt\nInt\n0\nInt\nString\ndefault\nright\ntrue\ntrue\n", mode: mode, root: root)
        }
    }
}
#endif
