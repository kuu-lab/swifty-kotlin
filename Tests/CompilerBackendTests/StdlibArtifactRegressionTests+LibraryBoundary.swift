@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    /// KUU-1683: `provideDelegate` returns an interface whose `getValue` has a
    /// default body. The delegate implementation lives behind a compiled
    /// library boundary and inherits its state from a generic parsing base,
    /// matching kotlinx-cli's `ArgumentValueDelegate` / `ParsingValue` shape.
    @Test
    func testMemberDelegateUsesInterfaceDefaultAcrossLibraryBoundary() throws {
        let librarySource = """
        package kotlinx.cli
        import kotlin.reflect.KProperty

        interface ArgumentValueDelegate<T> {
            var value: T
            operator fun getValue(thisRef: Any?, property: KProperty<*>): T = value
        }

        class ArgType<T : Any> {
            companion object {
                val Boolean: ArgType<kotlin.Boolean> = ArgType<kotlin.Boolean>()
            }
        }

        interface DefaultRequiredType {
            class Default : DefaultRequiredType
            class None : DefaultRequiredType
        }

        abstract class Descriptor<T : Any, TResult>(
            val type: ArgType<T>,
            val description: String? = null,
            val defaultValue: TResult? = null
        ) {
            val defaultValueSet: Boolean
                get() = defaultValue != null
        }

        class OptionDescriptor<T : Any, TResult>(
            type: ArgType<T>,
            description: String? = null,
            defaultValue: TResult? = null
        ) : Descriptor<T, TResult>(type, description, defaultValue)

        abstract class ParsingValue<T : Any, TResult : Any>(val descriptor: Descriptor<T, TResult>) {
            protected lateinit var parsedValue: TResult
            protected fun valueIsInitialized(): Boolean = this::parsedValue.isInitialized
            var valueOrigin: Boolean = false
            abstract fun isEmpty(): Boolean
            protected abstract fun saveValue(value: TResult)
            fun setDelegatedValue(value: TResult) {
                parsedValue = value
            }
            fun addDefaultValue() {
                if (descriptor.defaultValueSet) {
                    parsedValue = descriptor.defaultValue!!
                }
            }
        }

        abstract class AbstractArgumentSingleValue<T : Any>(descriptor: Descriptor<T, T>) :
            ParsingValue<T, T>(descriptor) {
            override fun isEmpty(): Boolean = !valueIsInitialized()
            override fun saveValue(value: T) {
                parsedValue = value
            }
        }

        internal class ArgumentSingleValue<T : Any>(descriptor: Descriptor<T, T>) :
            AbstractArgumentSingleValue<T>(descriptor), ArgumentValueDelegate<T> {
            override var value: T
                get() = if (!isEmpty()) parsedValue else parsedValue
                set(value) { setDelegatedValue(value) }
        }

        internal class ArgumentSingleNullableValue<T : Any>(descriptor: Descriptor<T, T>) :
            AbstractArgumentSingleValue<T>(descriptor), ArgumentValueDelegate<T?> {
            override var value: T?
                get() = if (!isEmpty()) parsedValue else null
                set(value) {
                    if (value != null) parsedValue = value
                }
        }

        internal class CLIEntityWrapper(var entity: CLIEntity<*>? = null)

        abstract class CLIEntity<TResult> internal constructor(
            val delegate: ArgumentValueDelegate<TResult>,
            internal val owner: CLIEntityWrapper
        ) {
            var value: TResult
                get() = delegate.value
                set(value) {
                    delegate.value = value
                }
            operator fun provideDelegate(thisRef: Any?, property: KProperty<*>): ArgumentValueDelegate<TResult> = delegate
        }

        abstract class Option<TResult> internal constructor(
            delegate: ArgumentValueDelegate<TResult>, owner: CLIEntityWrapper
        ) : CLIEntity<TResult>(delegate, owner)

        abstract class AbstractSingleOption<T : Any, TResult, D : DefaultRequiredType> internal constructor(
            delegate: ArgumentValueDelegate<TResult>, owner: CLIEntityWrapper
        ) : Option<TResult>(delegate, owner)

        class SingleNullableOption<T : Any> internal constructor(
            descriptor: OptionDescriptor<T, T>, owner: CLIEntityWrapper
        ) : AbstractSingleOption<T, T?, DefaultRequiredType.None>(ArgumentSingleNullableValue(descriptor), owner)

        class SingleOption<T : Any, D : DefaultRequiredType> internal constructor(
            descriptor: OptionDescriptor<T, T>, owner: CLIEntityWrapper
        ) : AbstractSingleOption<T, T, D>(ArgumentSingleValue(descriptor), owner)

        fun <T : Any> SingleNullableOption<T>.default(value: T): SingleOption<T, DefaultRequiredType.Default> {
            val source = delegate as ParsingValue<T, T>
            val newOption = SingleOption<T, DefaultRequiredType.Default>(
                OptionDescriptor(source.descriptor.type, source.descriptor.description, value), owner
            )
            owner.entity = newOption
            return newOption
        }

        open class ArgParser(val programName: String) {
            private var entity: CLIEntityWrapper? = null
            private var subcommand: Subcommand? = null
            fun <T : Any> option(type: ArgType<T>, description: String? = null): SingleNullableOption<T> {
                val wrapper = CLIEntityWrapper()
                val option = SingleNullableOption(OptionDescriptor<T, T>(type, description), wrapper)
                wrapper.entity = option
                entity = wrapper
                return option
            }
            fun subcommands(value: Subcommand) {
                subcommand = value
            }
            fun parse() {
                val child = subcommand
                if (child != null) {
                    child.parseOptions()
                } else {
                    parseOptions()
                }
            }
            protected fun parseOptions() {
                val value = entity!!.entity!!.delegate as ParsingValue<*, *>
                if (value.isEmpty()) value.addDefaultValue()
            }
        }

        abstract class Subcommand(val name: String, val actionDescription: String) : ArgParser(name) {
            abstract fun execute()
        }
        """

        let consumerSource = """
        package app
        import kotlinx.cli.ArgParser
        import kotlinx.cli.ArgType
        import kotlinx.cli.Subcommand
        import kotlinx.cli.default

        class Sub(name: String) : Subcommand(name, "desc") {
            val invert by option(ArgType.Boolean, description = "d").default(false)
            override fun execute() {
                val observed = invert
            }
        }

        private val topLevelParser = ArgParser("top")
        val topLevelInvert by topLevelParser.option(ArgType.Boolean, description = "d").default(false)

        fun main() {
            val parser = ArgParser("prog")
            val command = Sub("sub")
            parser.subcommands(command)
            parser.parse()
            topLevelParser.parse()
            command.execute()
            val observedTopLevel = topLevelInvert
        }
        """

        let libraryBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: libraryBase + ".kklib") }
        try withTemporaryFile(contents: librarySource) { librarySourcePath in
            let library = CompilerTestSupport.makeCompilationContext(
                inputs: [librarySourcePath],
                moduleName: "KotlinxCliDelegateShape",
                emit: .library,
                outputPath: libraryBase,
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try CompilerTestSupport.runToKIR(library)
            try assertNoDiagnosticErrors(library)
            try LoweringPhase().run(library)
            try CodegenPhase().run(library)

            try withTemporaryFile(contents: consumerSource) { consumerPath in
                let outputBase = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: outputBase) }
                let consumer = CompilerTestSupport.makeCompilationContext(
                    inputs: [consumerPath],
                    moduleName: "Kuu1683DelegateConsumer",
                    emit: .executable,
                    outputPath: outputBase,
                    searchPaths: [libraryBase + ".kklib"],
                    includeStdlib: false,
                    allowDefaultStdlibLibrary: false
                )
                try CompilerTestSupport.runToLowering(consumer)
                try assertNoDiagnosticErrors(consumer)
                try CodegenPhase().run(consumer)
                try LinkPhase().run(consumer)

                let result = try CommandRunner.run(executable: outputBase, arguments: [])
                #expect(result.exitCode == 0)
            }
        }
    }

    @Test
    func testThreadLocalTopLevelPropertyFromKlibIsIsolatedAcrossWorkers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let stdlib = try testStdlibArtifactPath()
        let librarySource = directory.appendingPathComponent("ThreadLocal.kt").path
        let libraryOutput = directory.appendingPathComponent("ThreadLocalLibrary").path
        try """
        @file:Suppress("DEPRECATION_ERROR")
        package fixture

        import kotlin.native.concurrent.ThreadLocal

        @ThreadLocal
        var value = 0
        """.write(toFile: librarySource, atomically: true, encoding: .utf8)

        let library = makeCompilationContext(
            inputs: [librarySource], moduleName: "ThreadLocalLibrary", emit: .library,
            outputPath: libraryOutput, stdlibLibraryPath: stdlib
        )
        try runToLowering(library)
        try assertNoDiagnosticErrors(library)
        try CodegenPhase().run(library)

        let consumerSource = """
        @file:Suppress("DEPRECATION_ERROR")
        @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

        import fixture.value
        import kotlin.native.concurrent.TransferMode
        import kotlin.native.concurrent.Worker

        fun main() {
            value = 7
            val worker = Worker.start()
            val future = worker.execute(TransferMode.SAFE, { Unit }) {
                val previous = value
                value = 9
                previous
            }
            println(future.result)
            println(value)
            worker.requestTermination(true)
        }
        """
        try withTemporaryFile(contents: consumerSource) { consumerPath in
            let output = directory.appendingPathComponent("consumer").path
            let consumer = makeCompilationContext(
                inputs: [consumerPath], moduleName: "ThreadLocalConsumer", emit: .executable,
                outputPath: output, searchPaths: [libraryOutput + ".kklib"], stdlibLibraryPath: stdlib
            )
            try runToLowering(consumer)
            try assertNoDiagnosticErrors(consumer)
            try CodegenPhase().run(consumer)
            try LinkPhase().run(consumer)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout == "0\n7\n")
        }
    }
}
