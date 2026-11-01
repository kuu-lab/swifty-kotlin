@testable import CompilerCore
import Testing

@Suite(.serialized)
struct CompanionBlocksAndExtensionsExecutionTests {
    @Test
    func blockMembersAndExtensionsExecuteThroughClassNames() throws {
        try compileAndRunKotlin(
            """
            var blockInitialized = false

            class BlockHost {
                companion {
                    val prefix = run { blockInitialized = true; "block:" }
                    fun value() = prefix + "member"
                }
            }

            class ExtensionHost
            companion val ExtensionHost.suffix = "extension"
            companion fun ExtensionHost.value() = "companion:"

            fun main() {
                println(BlockHost.value() + BlockHost.prefix)
                println(ExtensionHost.value() + ExtensionHost.suffix)
                println(blockInitialized)
            }
            """,
            expectedOutput: "block:memberblock:\ncompanion:extension\ntrue\n",
            moduleName: "CompanionBlocksAndExtensions",
            requireNoCompilerDiagnostics: true
        )
    }

    /// KUU-3821: `companion {}` blocks and a `companion object` share one
    /// companion scope on the JVM — every block property initializer runs
    /// eagerly inside that scope's <clinit> before the companion object's
    /// own body, so the init log is "ACBI" (block, block, object property,
    /// object init block) rather than deferred or interleaved differently.
    @Test
    func companionBlocksAndCompanionObjectInitializeInOneScope() throws {
        try compileAndRunKotlin(
            """
            var initLog = ""
            private fun init(tag: String, value: String): String { initLog += tag; return value }

            class Mixed {
                companion { val beforeObject = init("A", "before") }
                companion object {
                    val objectValue = init("B", "object")
                    init { initLog += "I" }
                }
                companion { val afterObject = init("C", "after") }
            }

            fun main() {
                println(Mixed.objectValue)
                println(Mixed.beforeObject)
                println(Mixed.afterObject)
                println(initLog)
            }
            """,
            expectedOutput: "object\nbefore\nafter\nACBI\n",
            moduleName: "CompanionBlockWithObjectInitOrder",
            requireNoCompilerDiagnostics: true
        )
    }

    /// KUU-3822: initializing a class whose companion scope is a
    /// `companion {}` block first initializes the supertype's companion
    /// blocks — the same superclass-chain-first order named companion
    /// objects follow on the JVM.
    @Test
    func companionBlocksInitializeSupertypeCompanionsFirst() throws {
        try compileAndRunKotlin(
            """
            var initOrder = ""

            open class Parent {
                companion {
                    val parentProp1: String = run { initOrder += "P1 "; "parent1" }
                    val parentProp2: String = run { initOrder += "P2 "; "parent2" }
                }
            }

            class Child : Parent() {
                companion {
                    val childProp1: String = run { initOrder += "C1 "; "child1" }
                    val childProp2: String = run { initOrder += "C2 "; "child2" }
                }
            }

            fun main() {
                println(Child.childProp1)
                println(initOrder)
            }
            """,
            expectedOutput: "child1\nP1 P2 C1 C2 \n",
            moduleName: "CompanionBlockSupertypeInitOrder",
            requireNoCompilerDiagnostics: true
        )
    }

    /// KUU-3823: an enum's `companion {}` block initializers run inside the
    /// enum's <clinit> after the enum entries — touching a block member
    /// must observe "12" (entry then block), never "21".
    @Test
    func enumCompanionBlockInitializesAfterEntries() throws {
        try compileAndRunKotlin(
            """
            var propertyInitLog = ""
            private fun initProperty(tag: String, value: String): String { propertyInitLog += tag; return value }

            enum class TriggeredByProperty(val value: String) {
                Entry(initProperty("1", "entry"));

                companion { val blockValue = initProperty("2", "block") }
            }

            fun main() {
                println(TriggeredByProperty.blockValue)
                println(propertyInitLog)
            }
            """,
            expectedOutput: "block\n12\n",
            moduleName: "EnumCompanionBlockAfterEntries",
            requireNoCompilerDiagnostics: true
        )
    }

    /// KUU-3827: an enum with only `companion {}` blocks still owns a
    /// synthetic companion for `values`/`valueOf`/`entries`, but the enum's
    /// <clinit> must also run the hidden `$CompanionBlocks` object's
    /// initializers — reading `entries` first then observing the shared
    /// init log yields "12" (entries, then block).
    @Test
    func enumEntriesTriggerCompanionBlockInitialization() throws {
        try compileAndRunKotlin(
            """
            var initOrder = ""

            enum class Foo(val f: String) {
                Alpha(run { initOrder += "1"; "alpha" });

                companion {
                    val blockProp: String = run { initOrder += "2"; "block" }
                }
            }

            fun main() {
                println(Foo.entries)
                println(initOrder)
            }
            """,
            expectedOutput: "[Alpha]\n12\n",
            moduleName: "EnumEntriesTriggerCompanionBlock",
            requireNoCompilerDiagnostics: true
        )
    }
}
