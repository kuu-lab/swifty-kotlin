#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// KUU-1407: declarations and modifier combinations that Kotlin/JVM rejects
// must produce diagnostics instead of being silently accepted.

private func semaContext(for source: String) throws -> CompilationContext {
    let ctx = makeContextFromSource(source, allowDefaultStdlibLibrary: false)
    try runSema(ctx)
    return ctx
}

@Suite(.serialized)
struct DeclarationPositionValidationTests {

    // MARK: - Declaration positions

    @Test func constValInsideClassIsRejected() throws {
        let ctx = try semaContext(for: """
            class C { const val x = 1 }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0403", in: ctx)
    }

    @Test func initBlockInsideInterfaceIsRejected() throws {
        let ctx = try semaContext(for: """
            interface I { init { } }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0408", in: ctx)
    }

    @Test func constructorInsideInterfaceIsRejected() throws {
        let ctx = try semaContext(for: """
            interface I { constructor(x: Int) }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0409", in: ctx)
    }

    @Test func dataInnerClassIsRejected() throws {
        let ctx = try semaContext(for: """
            class Outer { data inner class D(val x: Int) }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0402", in: ctx)
    }

    @Test func topLevelInnerClassIsRejected() throws {
        let ctx = try semaContext(for: """
            inner class D(val x: Int)
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func privateLocalVariableIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { private val x = 1 }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func internalLocalVariableIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { internal var y = 2 }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func privateLocalFunctionIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { private fun g() {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func localInterfaceIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { interface J { fun g() } }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0429", in: ctx)
    }

    @Test func localAnnotationClassIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { annotation class A(val x: Int) }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0429", in: ctx)
    }

    @Test func orphanActualIsRejected() throws {
        let ctx = try semaContext(for: """
            actual fun f(): Int = 1
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0410", in: ctx)
    }

    @Test func illegalOperatorNameIsRejected() throws {
        let ctx = try semaContext(for: """
            class C { operator fun notARealOp(): Int = 0 }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0416", in: ctx)
    }

    // MARK: - Annotation classes

    @Test func annotationMemberWithInvalidTypeIsRejected() throws {
        let ctx = try semaContext(for: """
            class SB
            annotation class A(val x: SB)
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0411", in: ctx)
    }

    @Test func annotationClassMembersAreRejected() throws {
        let ctx = try semaContext(for: """
            annotation class A(val x: Int) { fun f() {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0419", in: ctx)
    }

    @Test func annotationVarParameterIsRejected() throws {
        let ctx = try semaContext(for: """
            annotation class A(var x: Int)
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0427", in: ctx)
    }

    // MARK: - Functional interfaces

    @Test func funInterfaceWithTwoAbstractFunctionsIsRejected() throws {
        let ctx = try semaContext(for: """
            fun interface F { fun a(); fun b() }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0406", in: ctx)
    }

    @Test func funInterfaceWithZeroAbstractFunctionsIsRejected() throws {
        let ctx = try semaContext(for: """
            fun interface F { fun a() {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0406", in: ctx)
    }

    @Test func funInterfaceWithOneAbstractFunctionIsAccepted() throws {
        let ctx = try semaContext(for: """
            fun interface F { fun run(): Int; fun helper() = 1 }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0406", in: ctx)
    }

    // MARK: - Value classes

    @Test func valueClassVarParameterIsRejected() throws {
        let ctx = try semaContext(for: """
            @JvmInline value class V(var x: Int)
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0423", in: ctx)
    }

    @Test func dataValueClassIsRejected() throws {
        let ctx = try semaContext(for: """
            @JvmInline data value class V(val x: Int)
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0402", in: ctx)
    }

    @Test func sealedValueClassIsRejected() throws {
        let ctx = try semaContext(for: """
            @JvmInline sealed value class V(val x: Int)
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0420", in: ctx)
    }

    // MARK: - Modifier incompatibilities

    @Test func finalOpenFunctionIsRejected() throws {
        let ctx = try semaContext(for: """
            open class C { final open fun f() {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0402", in: ctx)
    }

    @Test func openEnumClassIsRejected() throws {
        let ctx = try semaContext(for: """
            open enum class E { A }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func sealedTopLevelFunctionIsRejected() throws {
        let ctx = try semaContext(for: """
            sealed fun f() {}
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func protectedInsideObjectIsRejected() throws {
        let ctx = try semaContext(for: """
            object O { protected fun f() {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
    }

    @Test func constructorInsideObjectIsRejected() throws {
        let ctx = try semaContext(for: """
            object O { constructor() }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0417", in: ctx)
    }

    @Test func companionInsideObjectIsRejected() throws {
        let ctx = try semaContext(for: """
            object O { companion object C }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
    }

    @Test func internalInsideInterfaceIsRejected() throws {
        let ctx = try semaContext(for: """
            interface I { internal fun f() {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
    }

    // MARK: - Enum / data / property constraints

    @Test func enumExtendingClassIsRejected() throws {
        let ctx = try semaContext(for: """
            open class B
            enum class E : B() { A }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0405", in: ctx)
    }

    @Test func emptyDataClassIsRejected() throws {
        let ctx = try semaContext(for: """
            data class D()
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0404", in: ctx)
    }

    @Test func uninitializedMemberPropertyIsRejected() throws {
        let ctx = try semaContext(for: """
            class C { val x: Int }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0424", in: ctx)
    }

    @Test func abstractMemberPropertyIsAccepted() throws {
        let ctx = try semaContext(for: """
            abstract class C { abstract val x: Int }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0424", in: ctx)
    }

    @Test func initBlockInitializedPropertyIsAccepted() throws {
        let ctx = try semaContext(for: """
            class C { val x: Int
                init { x = 1 } }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0424", in: ctx)
    }

    // MARK: - Expressions

    @Test func nonThrowableCatchIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { try {} catch (e: String) {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0413", in: ctx)
    }

    @Test func throwableCatchIsAccepted() throws {
        let ctx = try semaContext(for: """
            fun f() { try {} catch (e: Exception) {} }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0413", in: ctx)
    }

    @Test func nonThrowableThrowIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { throw "oops" }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0414", in: ctx)
    }

    @Test func throwableThrowIsAccepted() throws {
        let ctx = try semaContext(for: """
            fun f() { throw Exception() }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0414", in: ctx)
    }

    @Test func disjointIsCheckIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f(x: Int) = x is String
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0415", in: ctx)
    }

    @Test func genericStarIsCheckIsAccepted() throws {
        let ctx = try semaContext(for: """
            interface Flow<out T>
            class Impl<T>(val source: Flow<T>) : Flow<T>
            fun <T> f(source: Flow<T>) = source is Impl<*>
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0415", in: ctx)
    }

    @Test func constructorDelegationCycleIsRejected() throws {
        let ctx = try semaContext(for: """
            class C {
                constructor(x: Int) : this(x.toString())
                constructor(s: String) : this(s.length)
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0412", in: ctx)
    }

    // MARK: - Valid constructs stay silent

    @Test func validDeclarationsAreAccepted() throws {
        let ctx = try semaContext(for: """
            class Outer { inner class In(val x: Int) }
            object O { const val K = 1 }
            annotation class A(val x: Int, val s: String, val k: kotlin.reflect.KClass<*>)
            fun interface FI { fun run(): Int }
            @JvmInline value class V(val x: Int)
            data class D(val x: Int)
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0402", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0403", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0404", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0406", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0411", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0420", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0423", in: ctx)
    }

    @Test func privateMembersOfAnonymousObjectsAreAccepted() throws {
        // Regression: object-literal member prefixes share the local
        // declaration parser — `private` there is legal.
        let ctx = try semaContext(for: """
            fun f(): Iterator<Int> {
                val it = object : Iterator<Int> {
                    private var index = 0
                    override fun hasNext(): Boolean = index < 1
                    override fun next(): Int = index
                }
                return it
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func lateinitLocalVarIsAccepted() throws {
        let ctx = try semaContext(for: """
            fun f() { lateinit var s: String; s = "x" }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0418", in: ctx)
    }
}
#endif
