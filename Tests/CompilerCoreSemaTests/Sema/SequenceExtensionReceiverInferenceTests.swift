#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct SequenceExtensionReceiverInferenceTests {
    private let declarations = """
    import kotlin.sequences.SequenceScope
    class Path(val n: Int)
    suspend fun SequenceScope<Int>.yieldI(x: Int) { yield(x) }
    suspend fun SequenceScope<Path>.collect(path: Path) { yield(path) }
    suspend fun SequenceScope<Int>.collect(value: Int) { yield(value) }
    suspend fun <T> SequenceScope<T>.yieldValue(value: T) { yield(value) }
    fun accept(path: Path) {}
    """

    @Test
    func infersElementFromExtensionReceiver() throws {
        let statements = [
            "val s = sequence { yieldI(2) }; val n: Int = s.first() + 1",
            "val s = sequence { collect(Path(1)) }; val n: Int = s.first().n; accept(s.first())",
            "val s = iterator { collect(Path(1)) }; accept(s.next())",
            "val s = sequence { this.collect(Path(1)) }; accept(s.first())",
            "val s = sequence { yield(Path(1)); collect(Path(2)) }; accept(s.first())",
            "val s = sequence<Path> { collect(Path(1)) }; accept(s.first())",
            "val s: Sequence<Path> = sequence { collect(Path(1)) }; accept(s.first())",
            "val s = sequence { yieldValue(Path(1)) }; accept(s.first())",
            "val s = sequence { val nested = sequence { yieldI(2) }; collect(Path(1)) }; accept(s.first())",
            "val s = sequence { if (true) collect(Path(1)) else collect(Path(2)) }; accept(s.first())",
            "val s = sequence { listOf(1).forEach { collect(Path(it)) } }; accept(s.first())",
            "val s = sequence { with(0) { collect(Path(1)) } }; accept(s.first())",
        ]
        let functions = statements.enumerated().map { index, statement in
            "fun case\(index)() { \(statement) }"
        }.joined(separator: "\n")
        _ = try semaContext(
            from: declarations + "\n" + functions
        )
    }

    @Test
    func memberExtensionUsesBuilderExtensionReceiver() throws {
        _ = try semaContext(from: declarations + """

        class Owner {
            suspend fun SequenceScope<Path>.owned() { yield(Path(1)) }
            fun build() {
                val s = sequence { owned() }
                accept(s.first())
            }
        }
        """)
    }

    @Test
    func explicitOtherReceiverDoesNotConstrainBuilder() throws {
        _ = try semaContext(from: declarations + """

        suspend fun SequenceScope<Path>.outer(other: SequenceScope<Int>) {
            val s = sequence {
                other.yieldI(2)
                collect(Path(1))
            }
            accept(s.first())
        }
        """)
    }
}
#endif
