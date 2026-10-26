#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite struct ProjectedInheritedReceiverWriteTests {
    @Test(arguments: [
        "fun check(values: List<Any>) { if (values is MutableList<*>) values.add(Any()) }",
        "fun check(values: MutableList<*>) { values.add(Any()) }",
        "fun check(values: MutableList<out Number>) { values.add(1) }",
        "interface Sink<T> { fun put(value: T) }; interface Child<T>: Sink<T>; fun check(value: Child<out Number>) { value.put(1) }",
        "interface Read<out T>; interface Sink<T> { fun put(value: T) }; fun check(value: Read<Any>) { if (value is Sink<*>) value.put(Any()) }",
    ])
    func invariantStarChecksDoNotPermitWiderWrites(source: String) throws {
        let ctx = makeContextFromSource(source, emit: .jvmJar)
        try JVMPreparationPhase().run(ctx)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
    @Test(arguments: [
        "fun check(values: MutableList<Any>) { values.add(Any()) }",
        "fun check(values: MutableList<in String>) { values.add(\"one\") }",
        "interface Sink<T> { fun put(value: T) }; interface Child<T>: Sink<T>; fun check(value: Child<in String>) { value.put(\"one\") }",
    ])
    func invariantAndContravariantReceiversKeepWritableValues(source: String) throws {
        let ctx = makeContextFromSource(source, emit: .jvmJar)
        try JVMPreparationPhase().run(ctx)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }


    @Test(arguments: [
        "interface Sink<T> { fun put(value: T) }; interface Child<T>: Sink<T>; fun check(value: Child<*>) { value.put(stop()) }",
        "interface Sink<T> { fun put(value: T) }; fun check(value: Sink<*>) { value.put(stop()) }",
        "interface Sink<T> { fun put(first: T, second: T) }; interface Child<T>: Sink<T>; fun check(value: Child<*>) { value.put(second = stop(), first = stop()) }",
    ])
    func projectedInputsAcceptOnlyNonReturningArguments(source: String) throws {
        try check(source, accepted: true)
    }

    @Test(arguments: [
        "interface Sink<T> { fun put(value: T) }; interface Child<T>: Sink<T>; fun check(value: Child<*>) { value.put(null) }",
        "interface Sink<T> { fun put(value: T) }; interface Child<T>: Sink<T>; fun check(value: Child<*>) { value.put(nullableStop()) }",
        "interface Sink<T> { fun put(first: T, second: T) }; interface Child<T>: Sink<T>; fun check(value: Child<*>) { value.put(stop(), Any()) }",
        "interface Sink<T> { fun put(first: T, second: T) }; interface Child<T>: Sink<T>; fun check(value: Child<*>) { value.put(second = Any(), first = stop()) }",
        "interface Sink<T> { fun put(vararg values: T) }; interface Child<T>: Sink<T>; fun check(value: Child<*>) { value.put(stop(), Any()) }",
        "interface Sink<T> { fun put(value: T) }; interface Child<T>: Sink<T>; fun check(value: Child<in String>) { value.put(Any()) }",
    ])
    func bottomArgumentsDoNotHideOtherInvalidWrites(source: String) throws {
        try check(source, accepted: false)
    }

    @Test(arguments: [
        "interface Cell<T> { fun put(value: T); fun get(): T }; interface Child<T>: Cell<T>; fun check(value: Child<in String>): Any? { value.put(\"one\"); return value.get() }",
        "interface Cell<T> { fun get(): T }; interface Child<T>: Cell<T>; fun check(value: Child<out Number>): Number = value.get()",
        "interface Cell<T> { fun get(): T }; interface Child<T>: Cell<T>; fun check(value: Child<String>): String = value.get()",
        "interface Cell<out T> { fun put(value: @UnsafeVariance T): T }; interface Child<out T>: Cell<T>; fun check(value: Child<*>): Any? = value.put(Any())",
    ])
    func inheritedReadsAndUnsafeVarianceKeepTheirBounds(source: String) throws {
        try check(source, accepted: true)
    }

    @Test(arguments: [
        "interface Cell<T> { fun get(): T }; interface Child<T>: Cell<T>; fun check(value: Child<in String>): String = value.get()",
        "interface Cell<T> { fun get(): T }; interface Child<T>: Cell<T?>; fun check(value: Child<out Number>): Number = value.get()",
        "interface Sink<T> { fun put(value: T) }; interface Child<T>: Sink<T?>; fun check(value: Child<out Number>) { value.put(1) }",
        "interface Sink<T> { fun put(value: T) }; interface Child<T>: Sink<T?>; fun check(value: Child<*>) { value.put(Any()) }",
    ])
    func inheritedProjectionsDoNotWidenWritesOrNarrowReads(source: String) throws {
        try check(source, accepted: false)
    }

    @Test(arguments: [
        "interface Cell<T> { fun get(): T }; interface Child<T>: Cell<T?>; fun check(value: Child<out Number>): Number? = value.get()",
        "interface Sink<T> { fun put(value: T) }; interface Child<T>: Sink<T?>; fun check(value: Child<out Number>) { value.put(null) }",
        "interface Sink<T> { fun put(value: T) }; interface Child<T>: Sink<T?>; fun check(value: Child<*>) { value.put(null) }",
        "interface Sink<T> { fun put(value: T) }; interface Child<T>: Sink<T?>; fun check(value: Child<*>) { value.put(nullableStop()) }",
    ])
    func explicitlyNullableSupertypeInputsKeepNullWritable(source: String) throws {
        try check(source, accepted: true)
    }

    private func check(_ source: String, accepted: Bool) throws {
        let ctx = makeContextFromSource("""
        fun stop(): Nothing = throw IllegalStateException()
        fun nullableStop(): Nothing? = null
        \(source)
        """, emit: .jvmJar)
        try JVMPreparationPhase().run(ctx)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError != accepted, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
