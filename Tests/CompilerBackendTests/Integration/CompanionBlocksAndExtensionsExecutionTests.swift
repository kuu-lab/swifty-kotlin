@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
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
}
