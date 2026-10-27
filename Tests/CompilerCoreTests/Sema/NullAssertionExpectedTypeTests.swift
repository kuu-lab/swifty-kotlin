#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct NullAssertionExpectedTypeTests {
    private func check(_ source: String) throws {
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map(\.message))")
        }
    }

    @Test
    func infersOperandFromExpectedType() throws {
        try check("""
            fun <T> nullable(): T? = null
            val value: String = nullable()!!
            """)
    }

    @Test
    func infersExtensionDelegateConstructorFromReceiver() throws {
        try check("""
            class UserDataProperty<in R>(val key: String) {
                operator fun getValue(thisRef: R, desc: Any): String = key
                operator fun setValue(thisRef: R, desc: Any, value: String) {}
            }
            var String.calc: String by UserDataProperty("K")
            """)
    }

    @Test
    func infersExtensionFactoryWithAndWithoutNullAssertion() throws {
        try check("""
            class Ref<T>(val value: T)
            class Delegate<T>(val value: T)
            operator fun <T> Ref<T>.provideDelegate(host: Any?, prop: Any): Delegate<T> = Delegate(value)
            operator fun <T> Delegate<T>.getValue(host: Any?, prop: Any): T = value
            fun <T> List<Ref<*>>.getElement(index: Int): Ref<T> = this[index] as Ref<T>
            fun test(list: List<Ref<*>>) {
                val first: String by list.getElement(0)!!
                val second: String by list.getElement(0)
            }
            """)
    }

    @Test
    func infersImplicitReceiverExtensionFactory() throws {
        try check("""
            class TypeInference { val value: String by providerFun() }
            class Inv<T>(val x: T)
            fun <T, R> T.providerFun() = object : DelegateProvider<T, R>() {
                override fun provideDelegate(thisRef: T, property: Any): Inv<R> = Inv("OK") as Inv<R>
            }
            operator fun <T> Inv<T>.getValue(thisRef: Any?, property: Any): T = x
            abstract class DelegateProvider<T, R> {
                abstract operator fun provideDelegate(thisRef: T, property: Any): Inv<R>
            }
            """)
    }

    @Test
    func infersProviderFromMutablePropertySetter() throws {
        try check("""
            class Delegate<T>(val data: T)
            operator fun Delegate<*>.getValue(host: Any?, prop: Any): String = "OK"
            operator fun <T> Delegate<T>.setValue(host: Any?, prop: Any, value: T) {}
            operator fun <T> String.provideDelegate(host: Any?, prop: Any): Delegate<T> = Delegate(this as T)
            var value: String by "OK"
            var explicit: String by "OK".provideDelegate(null, "")
            """)
    }

    @Test
    func infersNestedConstructorFromInheritedDelegate() throws {
        try check("""
            class OptionDescriptor<T>
            interface ArgumentValueDelegate<T> {
                operator fun getValue(host: Any?, prop: Any): T
            }
            abstract class CLIEntity<T>(val delegate: ArgumentValueDelegate<T>) {
                operator fun provideDelegate(host: Any?, prop: Any): ArgumentValueDelegate<T> = delegate
            }
            abstract class AbstractOption<T : Any, R>(delegate: ArgumentValueDelegate<R>) : CLIEntity<R>(delegate)
            class NullableValue<T : Any>(descriptor: OptionDescriptor<T>) : ArgumentValueDelegate<T?> {
                override fun getValue(host: Any?, prop: Any): T? = null
            }
            class NullableOption<T : Any>(descriptor: OptionDescriptor<T>) : AbstractOption<T, T?>(NullableValue(descriptor))
            fun test() {
                val value: List<Any>? by NullableOption(OptionDescriptor())
            }
            """)
    }

    @Test
    func rejectsIncompatibleFactoryArgument() throws {
        let source = """
            class Delegate<T>(val value: T) {
                operator fun getValue(host: Any?, prop: Any): T = value
            }
            fun <T> delegate(value: T): Delegate<T> = Delegate(value)
            val property: String by delegate(1)
            """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
        }
    }

    @Test
    func dispatchesAbstractProvideDelegateVirtually() throws {
        let source = """
            class Owner { val value: String by provider() }
            class Inv<T>(val value: T)
            fun <T, R> T.provider(): Provider<T, R> = object : Provider<T, R>() {
                override fun provideDelegate(host: T, prop: Any): Inv<R> = Inv("OK") as Inv<R>
            }
            operator fun <T> Inv<T>.getValue(host: Any?, prop: Any): T = value
            abstract class Provider<T, R> {
                abstract operator fun provideDelegate(host: T, prop: Any): Inv<R>
            }
            """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "Owner", in: module, interner: ctx.interner)
            let name = ctx.interner.intern("provideDelegate")
            #expect(body.contains { instruction in
                guard case let .virtualCall(_, callee, _, _, _, _, _, .vtable(_)) = instruction else {
                    return false
                }
                return callee == name
            })
        }
    }

    @Test
    func dispatchesAbstractProviderForTopLevelAndLocalProperties() throws {
        let source = """
            class Delegate { operator fun getValue(host: Any?, prop: Any): String = "OK" }
            abstract class Provider {
                abstract operator fun provideDelegate(host: Any?, prop: Any): Delegate
            }
            fun provider(): Provider = object : Provider() {
                override fun provideDelegate(host: Any?, prop: Any): Delegate = Delegate()
            }
            val top: String by provider()
            fun local(): String {
                val value: String by provider()
                return value
            }
            fun main() {}
            """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError)
            let module = try #require(ctx.kir)
            let name = ctx.interner.intern("provideDelegate")
            for functionName in ["main", "local"] {
                let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
                #expect(body.contains { instruction in
                    guard case let .virtualCall(_, callee, _, _, _, _, _, .vtable(_)) = instruction else {
                        return false
                    }
                    return callee == name
                }, "Expected virtual provideDelegate in \(functionName)")
            }
        }
    }
}
#endif
