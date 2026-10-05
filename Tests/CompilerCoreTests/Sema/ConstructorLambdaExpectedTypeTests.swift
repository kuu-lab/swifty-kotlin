#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ConstructorLambdaExpectedTypeTests {
    @Test(arguments: [
        """
        open class Base(val transform: (Int) -> Int)
        object Derived : Base({ it + 1 })
        """,
        """
        open class Base(val transform: (Int) -> Int)
        class Derived(offset: Int) : Base({ it + offset })
        """,
        """
        open class Base<T>(val label: String = "base", val transform: (T) -> T)
        object Derived : Base<String>(transform = { it + "!" })
        """,
        """
        open class Base<T>(val transform: (T) -> T)
        class Derived : Base<Int> {
            constructor(offset: Int) : super({ it + offset })
        }
        """,
        """
        class Derived<T>(val transform: (T) -> T) {
            constructor(marker: Int) : this(transform = { it })
        }
        """,
        """
        open class Base<A, B>(val seed: A, val transform: (B) -> A)
        class Derived<T>(seed: T) : Base<T, Int>(seed, { seed })
        """,
        """
        open class Base<T>(val label: String = "base", val transform: (T) -> T)
        fun make(offset: Int) = object : Base<Int>(transform = { it + offset }) {}
        """,
        """
        open class Base<T>(val transform: (T) -> Int)
        object Derived : Base<String?>({ if (it == null) 0 else it.length })
        """,
        """
        open class Base {
            constructor(transform: (Int) -> Int, marker: Int)
            constructor(transform: (String) -> String, marker: String)
        }
        object Derived : Base({ it + 1 }, 7)
        """,
        """
        open class Base(val first: (Int) -> Int, val second: (String) -> String)
        object Derived : Base({ it + 1 }, { it + "!" })
        """,
        """
        open class Base(val transform: (Int) -> Int)
        fun make(offset: Int) {
            class Local : Base({ it + offset })
            object Named : Base({ it + offset })
        }
        """,
        """
        open class Base(val transform: (Int) -> Int)
        fun transform(value: Int): Int = value + 1
        fun transform(value: String): String = value + "!"
        object Derived : Base(::transform)
        """,
    ])
    func propagatesConstructorParameterTypes(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Constructor arguments should type-check: \(errors)")
        let sema = try #require(ctx.sema)
        #expect(!sema.bindings.constructorDelegationTargets.isEmpty)
    }

    @Test(arguments: [
        """
        open class Base(val transform: (Int) -> Int)
        object Derived : Base({ it.length })
        """,
        """
        open class Base(val transform: (Int) -> Int)
        class Derived : Base({ it + "wrong" })
        """,
        """
        open class Base<T>(val transform: (T) -> T)
        class Derived : Base<Int> {
            constructor(marker: Int) : super({ value: String -> value })
        }
        """,
        """
        open class Base<T>(val transform: (T) -> T)
        fun make() = object : Base<String>({ it - 1 }) {}
        """,
        """
        open class Base {
            constructor(transform: (Int) -> Int)
            constructor(transform: (String) -> String)
        }
        object Derived : Base({ it })
        """,
    ])
    func rejectsInvalidOrAmbiguousLambdaArguments(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Invalid constructor lambda must be rejected")
    }
}
#endif
