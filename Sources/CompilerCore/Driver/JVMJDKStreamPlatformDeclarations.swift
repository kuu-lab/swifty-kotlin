import Foundation

extension JVMClasspathIndex {
    /// Supplies the JDK 8 stream contracts while keeping their implementations in the JDK.
    func injectJDKStreamPlatformDeclarations(into ctx: CompilationContext) throws {
        func reference(_ name: String) -> JVMValueType {
            .reference(name, nullable: false)
        }
        func method(
            _ owner: String,
            _ name: String,
            _ parameters: [JVMValueType],
            _ result: JVMValueType,
            isStatic: Bool = false,
            isInterface: Bool = false,
            isAbstract: Bool = true
        ) -> JVMForeignMethod {
            JVMForeignMethod(
                owner: owner,
                name: name,
                descriptor: "(" + parameters.map(\.descriptor).joined() + ")" + result.descriptor,
                parameters: parameters,
                result: result,
                isStatic: isStatic,
                isInterface: isInterface,
                isAbstract: isAbstract
            )
        }

        let stream = reference("java/util/stream/Stream")
        let intStream = reference("java/util/stream/IntStream")
        let collector = reference("java/util/stream/Collector")
        let spliterator = reference("java/util/Spliterator")
        let function = reference("java/util/function/Function")
        let predicate = reference("java/util/function/Predicate")
        let consumer = reference("java/util/function/Consumer")
        let supplier = reference("java/util/function/Supplier")
        let toIntFunction = reference("java/util/function/ToIntFunction")
        let intConsumer = reference("java/util/function/IntConsumer")
        let intPredicate = reference("java/util/function/IntPredicate")
        let intUnaryOperator = reference("java/util/function/IntUnaryOperator")

        let declarations: [(String, String, UInt16, String?, [String], [JVMForeignMethod])] = [
            ("java/util/function/Function", """
            package java.util.function
            fun interface Function<T, R> { fun apply(value: T): R }
            """, 0x0601, "java/lang/Object", [], [
                method("java/util/function/Function", "apply", [.reference("java/lang/Object", nullable: true)], .reference("java/lang/Object", nullable: true), isInterface: true),
            ]),
            ("java/util/function/Predicate", """
            package java.util.function
            fun interface Predicate<T> { fun test(value: T): Boolean }
            """, 0x0601, "java/lang/Object", [], [
                method("java/util/function/Predicate", "test", [.reference("java/lang/Object", nullable: true)], .boolean, isInterface: true),
            ]),
            ("java/util/function/Consumer", """
            package java.util.function
            fun interface Consumer<T> { fun accept(value: T) }
            """, 0x0601, "java/lang/Object", [], [
                method("java/util/function/Consumer", "accept", [.reference("java/lang/Object", nullable: true)], .unit, isInterface: true),
            ]),
            ("java/util/function/Supplier", """
            package java.util.function
            fun interface Supplier<T> { fun get(): T }
            """, 0x0601, "java/lang/Object", [], [
                method("java/util/function/Supplier", "get", [], .reference("java/lang/Object", nullable: true), isInterface: true),
            ]),
            ("java/util/function/IntConsumer", """
            package java.util.function
            fun interface IntConsumer { fun accept(value: Int) }
            """, 0x0601, "java/lang/Object", [], [
                method("java/util/function/IntConsumer", "accept", [.int], .unit, isInterface: true),
            ]),
            ("java/util/function/IntPredicate", """
            package java.util.function
            fun interface IntPredicate { fun test(value: Int): Boolean }
            """, 0x0601, "java/lang/Object", [], [
                method("java/util/function/IntPredicate", "test", [.int], .boolean, isInterface: true),
            ]),
            ("java/util/function/IntUnaryOperator", """
            package java.util.function
            fun interface IntUnaryOperator { fun applyAsInt(value: Int): Int }
            """, 0x0601, "java/lang/Object", [], [
                method("java/util/function/IntUnaryOperator", "applyAsInt", [.int], .int, isInterface: true),
            ]),
            ("java/util/Spliterator", """
            package java.util
            interface Spliterator<T>
            """, 0x0601, "java/lang/Object", [], []),
            ("java/util/stream/Collector", """
            package java.util.stream
            interface Collector<T, A, R>
            """, 0x0601, "java/lang/Object", [], []),
            ("java/util/stream/Stream", """
            package java.util.stream
            import java.util.function.Consumer
            import java.util.function.Function
            import java.util.function.Predicate
            import java.util.function.ToIntFunction
            interface Stream<T> {
                fun <R> map(mapper: Function<in T, out R>): Stream<R>
                fun filter(predicate: Predicate<in T>): Stream<T>
                fun forEach(action: Consumer<in T>)
                fun count(): Long
                fun <R> collect(collector: Collector<in T, *, R>): R
                fun mapToInt(mapper: ToIntFunction<in T>): IntStream
            }
            """, 0x0601, "java/lang/Object", [], [
                method("java/util/stream/Stream", "map", [function], stream, isInterface: true),
                method("java/util/stream/Stream", "filter", [predicate], stream, isInterface: true),
                method("java/util/stream/Stream", "forEach", [consumer], .unit, isInterface: true),
                method("java/util/stream/Stream", "count", [], .long, isInterface: true),
                method("java/util/stream/Stream", "collect", [collector], .reference("java/lang/Object", nullable: true), isInterface: true),
                method("java/util/stream/Stream", "mapToInt", [toIntFunction], intStream, isInterface: true),
            ]),
            ("java/util/stream/IntStream", """
            package java.util.stream
            import java.util.function.IntConsumer
            import java.util.function.IntPredicate
            import java.util.function.IntUnaryOperator
            interface IntStream {
                fun sum(): Int
                fun count(): Long
                fun map(mapper: IntUnaryOperator): IntStream
                fun filter(predicate: IntPredicate): IntStream
                fun forEach(action: IntConsumer)
                fun boxed(): Stream<Int>
                companion object {
                    external fun range(startInclusive: Int, endExclusive: Int): IntStream
                }
            }
            """, 0x0601, "java/lang/Object", [], [
                method("java/util/stream/IntStream", "sum", [], .int, isInterface: true),
                method("java/util/stream/IntStream", "count", [], .long, isInterface: true),
                method("java/util/stream/IntStream", "map", [intUnaryOperator], intStream, isInterface: true),
                method("java/util/stream/IntStream", "filter", [intPredicate], intStream, isInterface: true),
                method("java/util/stream/IntStream", "forEach", [intConsumer], .unit, isInterface: true),
                method("java/util/stream/IntStream", "boxed", [], stream, isInterface: true),
                method("java/util/stream/IntStream", "range", [.int, .int], intStream, isStatic: true, isInterface: true, isAbstract: false),
            ]),
            ("java/util/stream/Collectors", """
            package java.util.stream
            class Collectors private constructor() {
                companion object {
                    external fun <T> toList(): Collector<T, *, kotlin.collections.List<T>>
                    external fun <T> toSet(): Collector<T, *, kotlin.collections.Set<T>>
                }
            }
            """, 0x0031, "java/lang/Object", [], [
                method("java/util/stream/Collectors", "toList", [], collector, isStatic: true, isAbstract: false),
                method("java/util/stream/Collectors", "toSet", [], collector, isStatic: true, isAbstract: false),
            ]),
            ("java/util/stream/StreamSupport", """
            package java.util.stream
            import java.util.Spliterator
            class StreamSupport private constructor() {
                companion object {
                    external fun <T> stream(spliterator: Spliterator<T>, parallel: Boolean): Stream<T>
                    external fun <T> stream(supplier: java.util.function.Supplier<Spliterator<T>>, characteristics: Int, parallel: Boolean): Stream<T>
                }
            }
            """, 0x0031, "java/lang/Object", [], [
                method("java/util/stream/StreamSupport", "stream", [spliterator, .boolean], stream, isStatic: true, isAbstract: false),
                method("java/util/stream/StreamSupport", "stream", [supplier, .int, .boolean], stream, isStatic: true, isAbstract: false),
            ]),
        ]

        for (name, source, flags, superclass, interfaces, methods) in declarations {
            let info = JVMClassInfo(name: name, flags: flags, superclass: superclass, interfaces: interfaces, methods: methods)
            let path = "<kswiftk-jvm>/stream/" + name + ".kt"
            guard !ctx.sourceManager.containsFile(path: path) else { throw JVMClassReader.Invalid() }
            let file = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8), origin: .residualStdlib)
            sourceClasses[file] = info
            if classes[name] == nil { classes[name] = info }
        }
    }
}
