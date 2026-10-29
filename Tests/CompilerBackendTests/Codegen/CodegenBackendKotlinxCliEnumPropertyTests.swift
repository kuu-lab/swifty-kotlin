@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CodegenBackendKotlinxCliEnumPropertyTests {

    /// KUU-3085: enum properties read through a star-projected parsing value
    /// must retain their enum type after Set.union and forEach.
    @Test
    func testEnumPropertyThroughStarProjectedSetUnionForEach() throws {
        let source = """
        class ArgParser {
            enum class ValueOrigin { SET_BY_USER, SET_DEFAULT_VALUE, UNSET, REDEFINED, UNDEFINED }

            private val options = mutableMapOf<String, ParsingValue<*, *>>()
            private val arguments = mutableMapOf<String, ParsingValue<*, *>>()

            fun addOption(value: ParsingValue<*, *>) { options["output"] = value }
            fun addArgument(value: ParsingValue<*, *>) { arguments["input"] = value }

            fun parse() {
                listOf(arguments, options).forEach { values ->
                    values.forEach { (_, value) -> value.valueOrigin = ValueOrigin.UNSET }
                }
                options["output"]!!.addValue()
                options.values.union(arguments.values).forEach { value ->
                    if (value.isEmpty()) value.addDefaultValue()
                    println(value.valueOrigin)
                    println(value.valueOrigin == ValueOrigin.SET_BY_USER)
                }
            }
        }

        interface ArgumentValueDelegate<T> { var value: T }

        internal abstract class ParsingValue<T : Any, TResult : Any> {
            protected lateinit var parsedValue: TResult
            var valueOrigin = ArgParser.ValueOrigin.UNDEFINED
                internal set

            abstract fun isEmpty(): Boolean
            protected abstract fun saveValue()
            fun addValue() { saveValue() }
            protected fun valueIsInitialized() = ::parsedValue.isInitialized
            fun addDefaultValue() {}
            fun setDelegatedValue(value: TResult) {
                parsedValue = value
                valueOrigin = ArgParser.ValueOrigin.REDEFINED
            }
        }

        internal abstract class AbstractArgumentSingleValue<T : Any> : ParsingValue<T, T>() {
            override fun isEmpty(): Boolean = !valueIsInitialized()
            override fun saveValue() {
                if (!isEmpty()) valueOrigin = ArgParser.ValueOrigin.SET_BY_USER
            }
            protected fun saveValue(value: T) {
                parsedValue = value
                valueOrigin = ArgParser.ValueOrigin.SET_BY_USER
            }
        }

        internal class ArgumentSingleValue<T : Any>(value: T? = null) :
            AbstractArgumentSingleValue<T>(), ArgumentValueDelegate<T> {
            init { value?.let { parsedValue = it } }
            override var value: T
                get() = if (!isEmpty()) parsedValue else error("Value isn't set")
                set(value) { setDelegatedValue(value) }
        }

        fun main() {
            val parser = ArgParser()
            parser.addOption(ArgumentSingleValue("out.txt"))
            parser.addArgument(ArgumentSingleValue<String>())
            parser.parse()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KUU3085EnumPropertySetUnion",
            expected: "SET_BY_USER\ntrue\nUNSET\nfalse\n",
            allowDefaultStdlibLibrary: false,
            prepareTestStdlibCache: false
        )
    }
}
