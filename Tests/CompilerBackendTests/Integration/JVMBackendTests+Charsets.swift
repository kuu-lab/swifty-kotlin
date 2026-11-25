#if canImport(Testing)
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func standardCharsetsLinkAsStaticFieldsAgainstOwnStdlib() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            import kotlin.text.Charsets;

            class CharsetConsumer {
                public static void main(String[] args) {
                    if (Charsets.INSTANCE == null) throw new AssertionError();
                    System.out.println(Charsets.UTF_8.name());
                    System.out.println(Charsets.UTF_16.name());
                    System.out.println(Charsets.UTF_16BE.name());
                    System.out.println(Charsets.UTF_16LE.name());
                    System.out.println(Charsets.UTF_32.name());
                    System.out.println(Charsets.UTF_32BE.name());
                    System.out.println(Charsets.UTF_32LE.name());
                    System.out.println(Charsets.US_ASCII.name());
                    System.out.println(Charsets.ISO_8859_1.name());
                }
            }
            """.write(to: root.appendingPathComponent("CharsetConsumer.java"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("javac", ["--release", "8", "-cp", library.path, "CharsetConsumer.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let output = try jvmTool("java", ["-Xverify:all", "-cp", root.path + ":" + library.path, "CharsetConsumer"], root: root)
            #expect(output.exitCode == 0, "\(output.stderr)")
            #expect(output.stdout == "UTF-8\nUTF-16\nUTF-16BE\nUTF-16LE\nUTF-32\nUTF-32BE\nUTF-32LE\nUS-ASCII\nISO-8859-1\n")
        }
    }

    @Test
    func accessorJvmNameRenamesPhysicalGetterAndSetter() throws {
        try withWorkspace { root in
            let source = #"""
            object Holder {
                private var cache: String? = null
                @get:JvmName("UTF32")
                val UTF_32: String get() = cache ?: "x".also { cache = it }
                @get:JvmName("flagOn") @set:JvmName("flagSet")
                var flag: Boolean = false
                @get:JvmName("""rawName""")
                val raw: Int = 1
                @get:JvmName(CONST_NAME)
                val viaConst: Int = 2
                @get:JvmName("\u0072eadEscaped")
                val escaped: Int = 3
                @get:JvmName("read" + "Joined")
                val joined: Int = 4
                @get:JvmName("readCount") @set:JvmName("writeCount")
                var count: UInt = 0u
            }
            object Shadow {
                const val CONST_NAME = "fromObject"
                @get:JvmName(CONST_NAME)
                val value: Int = 5
            }
            const val CONST_NAME = "constName"
            fun main() {
                println(Holder.UTF_32)
                Holder.flag = true
                println(Holder.flag)
                Holder.count = 7u
                println(Holder.count + Holder.raw.toUInt() + Holder.viaConst.toUInt())
            }
            """#
            let runtime = try m11Runtime()
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: runtime.components(separatedBy: ":"))
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + runtime, "MainKt"])
            #expect(run.stdout == "x\ntrue\n10\n")
            let listing = try jvmTool("javap", ["-cp", app.path + ":" + runtime, "Holder"], root: root)
            #expect(listing.stdout.contains("UTF32()"))
            #expect(listing.stdout.contains("flagOn()"))
            #expect(listing.stdout.contains("flagSet(boolean)"))
            #expect(!listing.stdout.contains("getUTF_32"))
            #expect(listing.stdout.contains("rawName()"))
            #expect(listing.stdout.contains("constName()"))
            #expect(listing.stdout.contains("readEscaped()"))
            let shadow = try jvmTool("javap", ["-cp", app.path + ":" + runtime, "Shadow"], root: root)
            #expect(shadow.stdout.contains("fromObject()"))
            #expect(!shadow.stdout.contains("constName()"))
            #expect(listing.stdout.contains("readJoined()"))
            #expect(listing.stdout.contains("readCount()"))
            #expect(listing.stdout.contains("writeCount(int)"))
        }
    }
}
#endif
