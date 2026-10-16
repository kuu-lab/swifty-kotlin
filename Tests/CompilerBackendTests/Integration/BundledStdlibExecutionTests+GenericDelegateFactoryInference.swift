@testable import CompilerCore
import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testGenericDelegateFactoryInferenceFromConventionContext(
        useArtifact: Bool,
        optimization: Int
    ) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlinSources(
            [
                """
                // Source: JetBrains/Kotlin v2.3.10 at 679366a83f99851b42f64795f10ed803ff011c73,
                // compiler/testData/codegen/box/delegatedProperty/provideDelegate/commonCaseForInference.kt
                // SHA-256: b7880fc545aa8b720a6e4201dcc8b80db67c7874df085f48dbd8947d8dde636d.
                object CommonCase {
                    interface Fas<D, E, R>
                    fun <D, E, R> delegate(): Fas<D, E, R> = object : Fas<D, E, R> {}
                    operator fun <D, E, R> Fas<D, E, R>.provideDelegate(host: D, p: Any?): Fas<D, E, R> = this
                    operator fun <D, E, R> Fas<D, E, R>.getValue(receiver: E, p: Any?): R = "OK" as R

                    val Long.test1: String by delegate()
                    val Long.test2: String by delegate<CommonCase, Long, String>()
                    val typed: Fas<CommonCase, Long, String> = delegate()
                    val Long.test3: String by typed
                }

                fun box() = with(CommonCase) {
                    require(3L.test1 == "OK" && 3L.test2 == "OK" && 3L.test3 == "OK")
                    "OK"
                }
                """,
                """
                object Host {
                    class Delegate<D, E, R>
                    fun <D, E, R> delegate(): Delegate<D, E, R> = Delegate()
                    fun <D, E, R> delegate(required: Int): MemberDelegate<D, E, R> = MemberDelegate()
                    operator fun <D, E, R> Delegate<D, E, R>.provideDelegate(host: D, p: Any?): Delegate<D, E, R> = this
                    operator fun <D, E, R> Delegate<D, E, R>.getValue(receiver: E, p: Any?): R = "OK" as R

                    val Long.value: String by delegate()
                    val Long.priority: String by delegate()
                    val Long.explicitTypeArguments: String by delegate<Host, Long, String>()
                    val typed: Delegate<Host, Long, String> = delegate()
                    val Long.explicitExpectedType: String by typed

                    fun checkDelegates(): String = with(this) {
                        require(1L.value == "OK")
                        require(1L.priority == "OK")
                        require(1L.explicitTypeArguments == "OK")
                        require(1L.explicitExpectedType == "OK")
                        "OK"
                    }
                }

                operator fun <D, E, R> Host.Delegate<D, E, R>.provideDelegate(host: Any?, p: Any?): Host.Delegate<D, E, R> = this

                class MemberDelegate<D, E, R> {
                    operator fun provideDelegate(host: D, p: Any?): MemberDelegate<D, E, R> = this
                    operator fun getValue(receiver: E, p: Any?): R = "OK" as R
                }
                fun <D, E, R> memberDelegate(): MemberDelegate<D, E, R> = MemberDelegate<D, E, R>()
                object MemberHost {
                    val Long.memberValue: String by memberDelegate()
                    fun checkDelegate(): String = with(this) {
                        require(1L.memberValue == "OK")
                        "OK"
                    }
                }

                open class BaseDelegate<D, E, R> {
                    operator fun provideDelegate(host: D, p: Any?): BaseDelegate<D, E, R> = this
                    operator fun getValue(receiver: E, p: Any?): R = "OK" as R
                }
                class DerivedDelegate<D, E, R> : BaseDelegate<D, E, R>()
                fun <D, E, R> inheritedDelegate(): DerivedDelegate<D, E, R> = DerivedDelegate()
                object InheritedHost {
                    val Long.inheritedValue: String by inheritedDelegate()
                    fun checkDelegate(): String = with(this) {
                        require(1L.inheritedValue == "OK")
                        "OK"
                    }
                }

                class GetterOnlyDelegate<E, R>
                fun <E, R> getterOnlyDelegate(): GetterOnlyDelegate<E, R> = GetterOnlyDelegate()
                operator fun <E, R> GetterOnlyDelegate<E, R>.getValue(receiver: E, p: Any?): R = "OK" as R
                object GetterOnlyHost {
                    val Long.getterOnlyValue: String by getterOnlyDelegate()
                    fun checkDelegate(): String = with(this) {
                        require(1L.getterOnlyValue == "OK")
                        "OK"
                    }
                }

                fun main() {
                    check(box() == "OK")
                    check(Host.checkDelegates() == "OK")
                    check(MemberHost.checkDelegate() == "OK")
                    check(InheritedHost.checkDelegate() == "OK")
                    check(GetterOnlyHost.checkDelegate() == "OK")
                    println("OK")
                }
                """,
            ],
            expectedOutput: "OK\n",
            moduleName: "KUU2277GenericDelegateFactoryInference",
            allowDefaultStdlibLibrary: useArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "",
            // Source injection currently reports the existing KSP-002 coroutine stub warning.
            // Compilation errors still fail through assertCompilationSucceeded.
            requireNoCompilerDiagnostics: useArtifact
        )
    }
}
