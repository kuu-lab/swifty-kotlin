@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendMutableCollectionDispatchTests {
    @Test(arguments: [true, false])
    func nestedGenericOverridesPreserveExactClassMatching(useArtifact: Bool) throws {
        let source = """
        interface Reader<T> {
            fun read(values: List<List<T>>): String = "default"
        }
        class IntReader : Reader<Int> {
            fun read(values: Set<List<Int>>): String = "wrong"
            override fun read(values: List<List<Int>>): String = "nested"
        }
        class DefaultReader : Reader<Int> {
            fun read(values: Set<List<Int>>): String = "wrong"
        }
        fun main() {
            val reader: Reader<Int> = IntReader()
            val inherited: Reader<Int> = DefaultReader()
            println(reader.read(listOf(listOf(1))))
            println(inherited.read(listOf(listOf(1))))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NestedGenericOverrideDispatch",
            expected: "nested\ndefault\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    @Test(arguments: [true, false])
    func mutationExceptionsReachCatch(useArtifact: Bool) throws {
        let source = try diffCaseSource("mutable_collection_throwing_override.kt")
        try assertKotlinOutput(
            source,
            moduleName: "MutableCollectionThrowingDispatch",
            expected: "remove:true\nclear:override\nadd:override\naddAll:override\nremoveAll:override\nretainAll:true\ncontinued\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    @Test(arguments: [true, false])
    func mutationsReachSourceOverrides(useArtifact: Bool) throws {
        let source = try diffCaseSource("ksp1069_custom_mutable_collection.kt")
        try assertKotlinOutput(
            source,
            moduleName: "MutableCollectionDispatch",
            expected: "true\ntrue\n[1, 2, 3, 4]\nfalse\ntrue\nfalse\ntrue\nfalse\n[1, 3, 4, 6]\ntrue\nfalse\n[1, 6]\n1\n[6]\n[]\narrAARRTTc\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}
