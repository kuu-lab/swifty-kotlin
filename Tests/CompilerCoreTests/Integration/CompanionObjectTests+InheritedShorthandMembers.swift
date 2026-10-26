#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension CompanionObjectTests {
    @Test func protectedInheritedCompanionMemberIsCallableFromEnclosingClass() throws {
        let source = """
        open class A { protected fun foo() = "OK" }
        class B {
            companion object : A()
            fun bar() = foo()
            fun invalidReceiver(value: A) = value.foo()
        }
        fun main() { println(B().bar()) }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0041" }.count == 1)
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0023" })
    }

    @Test func testBaseCompanionMembersResolveUnqualifiedInDerivedInstanceMembers() throws {
        let source = """
        open class Root {
            val inheritedProperty: Int = 1
            fun baseMember(): Int = EOF
            companion object {
                const val EOF: Int = -1
                const val ROOT_VALUE: Int = 42
            }
        }
        open class Middle : Root()
        class Derived : Middle() {
            companion object {
                const val OWN_VALUE: Int = 7
            }

            fun current(): Int = EOF
            fun inheritedFromGrandparent(): Int = ROOT_VALUE
            fun ownCompanion(): Int = OWN_VALUE
            fun qualifiedBaseCompanion(): Int = Root.EOF
            fun inheritedInstanceMember(): Int = inheritedProperty
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: ["", "Factory"])
    func testInheritedCompanionShorthandMembers(companionName: String) throws {
        let qualifier = companionName.isEmpty ? "Companion" : companionName
        let source = """
        open class Root<T> {
            open fun who(): String = "root"
            fun echo(value: T): T = value
            fun choose(value: Int): Int = value
            open val tag: String get() = "root-tag"
            val generic: T get() = echoValue()
            open fun echoValue(): T = throw IllegalStateException()
        }
        open class Base : Root<String>()
        class WithComp {
            fun who(): Int = 99
            val tag: Int = 99
            companion object \(companionName) : Base() {
                override fun who(): String = "companion"
                override fun echoValue(): String = "generic"
                fun choose(value: String): String = value
                fun make(): Int = 1
            }
        }
        fun check() {
            val explicit: String = WithComp.\(qualifier).who()
            val shorthand: String = WithComp.who()
            val tag: String = WithComp.tag
            val generic: String = WithComp.generic
            val echoed: String = WithComp.echo("echo")
            val inheritedOverload: Int = WithComp.choose(2)
            val ownOverload: String = WithComp.choose("own")
            val own: Int = WithComp.make()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: ["private", "protected"])
    func testInheritedCompanionShorthandRejectsInaccessibleMembers(visibility: String) throws {
        let source = """
        open class Base {
            \(visibility) fun hidden(): Int = 1
            \(visibility) val secret: Int = 2
        }
        class WithComp { companion object : Base() }
        fun check() {
            WithComp.hidden()
            WithComp.secret
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let code = visibility == "private" ? "KSWIFTK-SEMA-0040" : "KSWIFTK-SEMA-0041"
        #expect(ctx.diagnostics.diagnostics.filter { $0.code == code }.count == 2)
    }

    @Test func testCompanionShorthandDoesNotExposeOwnerInstanceMembers() throws {
        let source = """
        class WithComp {
            fun instanceOnly(): Int = 1
            val instanceProperty: Int = 2
            companion object
        }
        fun check() {
            WithComp.instanceOnly()
            WithComp.instanceProperty
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0024" }.count == 2)
    }
}
#endif
