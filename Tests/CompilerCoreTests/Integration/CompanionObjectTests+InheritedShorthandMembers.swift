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

    @Test func testProtectedCompanionMembersInNestedClasses() throws {
        let source = """
        open class A {
            companion object { protected fun foo(): String = "OK" }
            fun outer(): String = foo()
            class B : A() { fun bar(): String = foo() }
            class C { fun bar(): String = foo() }
        }
        fun outside(): String = A.foo()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0041")
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

    /// KUU-3766: unqualified access to a `private` member declared on a
    /// companion object's supertype must report the inaccessible member
    /// (matching kotlinc's "cannot access ... it is private"), not an
    /// unresolved reference or function.
    @Test func testUnqualifiedInheritedPrivateCompanionMemberReportsInaccessible() throws {
        let source = """
        open class Base {
            private fun hidden(): Int = 1
            private var secret: Int = 2
        }
        class WithComp {
            companion object : Base()
            fun callHidden(): Int = hidden()
            fun readSecret(): Int = secret
            fun refHidden(): () -> Int = ::hidden
            fun writeSecret() { secret = 5 }
            class Inner {
                fun nestedCall(): Int = hidden()
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0040" }.count == 5,
            "\(ctx.diagnostics.diagnostics)"
        )
        #expect(!ctx.diagnostics.diagnostics.contains {
            ["KSWIFTK-SEMA-0013", "KSWIFTK-SEMA-0022", "KSWIFTK-SEMA-0023"].contains($0.code)
        })
    }

    /// The same implicit-receiver hierarchy probe covers `private` members on
    /// the class's own supertype, not only the companion's (KUU-3766).
    @Test func testUnqualifiedPrivateSupertypeMemberReportsInaccessible() throws {
        let source = """
        open class Base {
            private fun hidden(): Int = 1
            private val secret: Int = 2
        }
        class Sub : Base() {
            fun callHidden(): Int = hidden()
            fun readSecret(): Int = secret
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0040" }.count == 2,
            "\(ctx.diagnostics.diagnostics)"
        )
        #expect(!ctx.diagnostics.diagnostics.contains {
            ["KSWIFTK-SEMA-0022", "KSWIFTK-SEMA-0023"].contains($0.code)
        })
    }

    /// A name absent from every implicit receiver hierarchy still reports the
    /// unresolved-function diagnostic (KUU-3766).
    @Test func testUnqualifiedTrulyMissingMemberStillReportsUnresolved() throws {
        let source = """
        open class Base {
            private fun hidden(): Int = 1
        }
        class WithComp {
            companion object : Base()
            fun probe(): Int = missing()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0023" }.count == 1)
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0040" })
    }

    /// A `private` member declared on the companion itself (not a supertype)
    /// remains accessible from the enclosing class (KUU-3766).
    @Test func testCompanionOwnPrivateMemberStaysAccessible() throws {
        let source = """
        class WithComp {
            companion object {
                private fun hidden(): Int = 1
            }
            fun probe(): Int = hidden()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
