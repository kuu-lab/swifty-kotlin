@testable import CompilerCore
import Testing

@Suite
struct ReflectKCallableSourceTests {
    private static let fixture = SemaFixture(surface: "KCallable")

    @Test func bundledContractHasSourceBackedMembers() throws {
        let (sema, interner) = try Self.fixture.shared()
        let owner = ["kotlin", "reflect", "KCallable"].map(interner.intern)
        for name in ["call", "callBy", "parameters", "typeParameters", "visibility", "isFinal", "isOpen", "isAbstract", "isSuspend", "annotations"] {
            let member = try #require(sema.symbols.lookup(fqName: owner + [interner.intern(name)]))
            #expect(sema.symbols.isSourceBackedSymbol(member))
            #expect(sema.symbols.symbol(member)?.flags.contains(.synthetic) == false)
        }
        let callable = try #require(sema.symbols.lookup(fqName: owner))
        let layout = try #require(sema.symbols.nominalLayout(for: callable))
        #expect(layout.vtableSize == 2)
    }

    @Test func referencesResolveInheritedCallableContract() throws {
        _ = try Self.fixture.make(source: """
        import kotlin.reflect.KCallable
        class C(var v: Int) { fun f(x: Int) = x * 2 }
        fun top(a: Int = 4) = a + 1
        fun check() {
            val function = ::top
            val callable: KCallable<Int> = ::top
            val erasedResult: Int = callable.call(1)
            val result: Int = function.call(1)
            val parameters = function.parameters
            val defaultResult: Int = function.callBy(emptyMap())
            val isFinal: Boolean = function.isFinal
            val memberResult: Int = C::f.call(C(3), 21)
            val constant: Boolean = C::v.isConst
            val late: Boolean = C::v.isLateinit
            val getterResult: Int = C::v.getter.call(C(3))
            C::v.setter.call(C(3), 9)
            val directGetter: Int = C::v.getter(C(3))
            C::v.setter(C(3), 10)
        }
        """)
    }
}
