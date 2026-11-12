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
                    System.out.println(Charsets.US_ASCII.name());
                    System.out.println(Charsets.ISO_8859_1.name());
                }
            }
            """.write(to: root.appendingPathComponent("CharsetConsumer.java"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("javac", ["--release", "8", "-cp", library.path, "CharsetConsumer.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let output = try jvmTool("java", ["-Xverify:all", "-cp", root.path + ":" + library.path, "CharsetConsumer"], root: root)
            #expect(output.exitCode == 0, "\(output.stderr)")
            #expect(output.stdout == "UTF-8\nUTF-16\nUTF-16BE\nUTF-16LE\nUS-ASCII\nISO-8859-1\n")
        }
    }
}
#endif
