@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {

    /// KUU-3214 / KT-83308: a virtual `toString()` call through the
    /// `kotlin.Any.toString` vtable slot must use the runtime's raw
    /// `(Int) -> Int` string-handle ABI. Registered entries are either
    /// `kk_any_member_to_string` or a `kk_any_to_string_bridge_*` raw
    /// bridge, so typing the indirect call as a flat String aggregate
    /// made the callee read uninitialized memory and the result came
    /// back null.
    @Test
    func testInheritedToStringVirtualCallUsesRawAnySlotABI() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        open class Base {
            override fun toString(): String = "base"
        }
        open class Child : Base() {
            override fun toString(): String = "child"
        }
        class Leaf : Child()
        fun describe(b: Base): String = b.toString()
        fun main() {
            println(Leaf().toString())
            println(describe(Child()))
            println(describe(Base()))
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }

            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "KUU3214InheritedToStringArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "child\nchild\nbase\n"
            )
        }
    }

    /// KUU-3214 / KT-83308: `by` delegation through a private-constructor
    /// abstract class plus a deep generic interface hierarchy returned
    /// null from `group<String, String>().toString()`.
    @Test
    func testDelegatedToStringThroughDeepInterfaceHierarchy() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        interface Node

        internal class NodeImpl : Node

        interface BsonNode : Node {
            override fun toString(): String
        }

        abstract class AbstractBsonNode private constructor(
            private val node: NodeImpl,
        ) : Node by node, BsonNode {

            constructor() : this(NodeImpl())

            final override fun toString(): String = "OK"
        }

        interface CompoundNode<N : Node>

        interface CompoundBsonNode : BsonNode, CompoundNode<BsonNode>

        abstract class AbstractCompoundBsonNode() : AbstractBsonNode(), CompoundBsonNode

        interface ValueOperators

        interface ValueAccumulators<From : Any, Into : Any> : ValueOperators, CompoundBsonNode

        interface ArithmeticValueAccumulators<From : Any, Into : Any> : ValueAccumulators<From, Into>

        interface AggregationOperators : ValueOperators

        interface AccumulationOperators<From : Any, Into : Any> : ValueAccumulators<From, Into>,
            AggregationOperators,
            ArithmeticValueAccumulators<From, Into>

        internal class AccumulationOperatorsImpl<From : Any, Into : Any>(
        ) : AbstractCompoundBsonNode(),
            AccumulationOperators<From, Into>

        internal fun <Document : Any, Out : Any> group() = AccumulationOperatorsImpl<Document, Out>()

        fun box(): String {
            return group<String, String>().toString()
        }

        fun main() {
            println(box())
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }

            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "KUU3214DelegatedToStringArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "OK\n")
        }
    }
}
