#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func implicitOuterExtensionReceiversSurviveNestedLambdas(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM10("""
            class Decoder(val value: Int)
            class Buffer
            fun withBuffer(block: Buffer.() -> Int): Int = Buffer().block()
            fun Buffer.nested(block: String.() -> Int): Int = "inner".block()
            inline fun Buffer.inlined(block: String.() -> Int): Int = "inline".block()
            fun Decoder.decodeImpl(max: Int): Int = value + max
            fun Decoder.single(max: Int): Int = withBuffer { decodeImpl(max) }
            fun Decoder.nestedDecode(max: Int): Int = withBuffer { nested { decodeImpl(max) } }
            fun Decoder.inlineDecode(max: Int): Int = withBuffer { inlined { decodeImpl(max) } }
            fun Decoder.explicit(max: Int): Int = withBuffer { nested { this@explicit.decodeImpl(max) } }
            fun Decoder.objectDecode(max: Int): Int {
                val action = object { fun run(): Int = withBuffer { nested { decodeImpl(max) } } }
                return action.run()
            }
            fun String.score(): Int = this.length
            fun String.outer(): Int = withBuffer { nested { score() } }
            fun withTextBuffer(block: Buffer.() -> String): String = Buffer().block()
            fun String.changed(): String = withTextBuffer { replace("a", "x") }
            fun String.explicitChanged(): String = withTextBuffer { this@explicitChanged.replace("a", "x") }
            fun Any.smartChanged(): String = if (this is String) replace("a", "x") else "other"
            fun String.outerPattern(): String = withTextBuffer { toRegex().pattern }
            fun String.explicitPattern(): String = withTextBuffer { this@explicitPattern.toRegex().pattern }
            class Host(val extra: Int) {
                fun Decoder.adjusted(): Int = value + extra
                fun <T : Decoder> T.genericAdjusted(): Int = value + extra
                fun Decoder.read(): Int = withBuffer { nested { adjusted() } }
                fun Decoder.genericRead(): Int = withBuffer { nested { genericAdjusted() } }
                fun Decoder.explicitGenericRead(): Int = withBuffer { this@explicitGenericRead.genericAdjusted() }
                fun run(): Int = Decoder(4).read()
                fun genericRun(): Int = Decoder(4).genericRead()
                fun explicitGenericRun(): Int = Decoder(4).explicitGenericRead()
            }
            fun main() {
                println(Decoder(7).single(3))
                println(Decoder(20).nestedDecode(4))
                println(Decoder(8).inlineDecode(2))
                println(Decoder(10).explicit(5))
                println(Decoder(12).objectDecode(5))
                println("outer".outer())
                println(Host(6).run())
                println("aba".changed())
                println("aba".explicitChanged())
                println(Host(6).genericRun())
                println(Host(6).explicitGenericRun())
                println("aba".smartChanged())
                println("aba".outerPattern())
                println("aba".explicitPattern())
            }
            """, expected: "10\n24\n10\n15\n17\n5\n10\nxbx\nxbx\n10\n10\nxbx\naba\naba\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [
        "class Buffer; class Host { fun <T : Decoder> T.adjusted(): Int = value; fun read(): Int = withBuffer { adjusted() } }",
        "class Buffer; class Host { fun <T : Decoder> T.adjusted(): Int = value; fun Decoder.read(): Int = withBuffer { adjusted<String>() } }",
    ])
    func genericOuterExtensionReceiversKeepUpperBoundRejections(source: String) throws {
        try withWorkspace { root in
            let result = try compile("class Decoder(val value: Int); fun withBuffer(block: Buffer.() -> Int): Int = Buffer().block(); " + source, root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
        }
    }
}
#endif
