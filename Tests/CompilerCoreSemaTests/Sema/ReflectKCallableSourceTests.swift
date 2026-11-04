@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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

    /// KUU-4088: a callable reference satisfies `F : KCallable<R>` /
    /// `F : KFunction<R>` bounds — the reference's return type binds R.
    /// Property references qualify too; this is the assertk `having` shape.
    @Test func callableReferenceSatisfiesKCallableTypeParameterBound() throws {
        _ = try Self.fixture.make(source: """
        import kotlin.reflect.KCallable
        import kotlin.reflect.KFunction
        class Person(val name: String, val age: Int)
        fun <R, F> useK(c: F): String where F : KCallable<R> = c.name
        fun <R, F> useKFn(c: F): String where F : KFunction<R> = c.name
        fun <F> useKStar(c: F): String where F : KCallable<*> = c.name
        fun <R> take(c: KCallable<R>): String = c.name
        fun <T, R, F> having(subject: T, callable: F): String where F : (T) -> R, F : KCallable<R> = callable.name
        fun inc(x: Int) = x + 1
        fun greet(p: Person) = "hi"
        fun check() {
            useK(::inc)
            useKFn(::inc)
            useKStar(::inc)
            take(::inc)
            useK(Person::name)
            val p = Person("a", 1)
            having(p, Person::name)
            having(p, Person::age)
            having(p, ::greet)
        }
        """)
    }

    /// KUU-4088 parity: a plain lambda still cannot satisfy `F : KCallable<R>`
    /// — lambdas carry no reflective contract, so kotlinc rejects them too.
    @Test func lambdaDoesNotSatisfyKCallableTypeParameterBound() throws {
        try withTemporaryFiles(contents: ["""
        import kotlin.reflect.KCallable
        fun <R, F> useK(c: F): String where F : KCallable<R> = c.name
        fun check() { useK { x: Int -> x + 1 } }
        """]) { paths in
            let ctx = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.contains { $0.code == "KSWIFTK-TYPE-0001" },
                "Expected KSWIFTK-TYPE-0001 for a lambda against a KCallable bound, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }
}
