#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func legacyPropertyReferenceConstructorsAcceptKotlinClassContainers() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            import kotlin.jvm.internal.MutablePropertyReference1Impl;
            import kotlin.jvm.internal.PropertyReference1;
            import kotlin.jvm.internal.PropertyReference1Impl;
            import kotlin.jvm.internal.Reflection;
            import kotlin.reflect.KDeclarationContainer;

            public final class Driver {
                public String getName() { return "test"; }
                public void setName(String name) {}
                public static void main(String[] args) {
                    KDeclarationContainer owner = Reflection.getOrCreateKotlinClass(Driver.class);
                    PropertyReference1 reference = new PropertyReference1Impl(owner, "name", "getName()Ljava/lang/String;");
                    var read = Reflection.property1(reference);
                    var write = new MutablePropertyReference1Impl(owner, "name", "getName()Ljava/lang/String;");
                    System.out.println(read.getName() + "/" + write.getName());
                }
            }
            """.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            let compile = try jvmTool("javac", ["-cp", stdlib.path, "Driver.java"], root: root)
            try #require(compile.exitCode == 0, "\(compile.stderr)")
            let run = try java(["-Xverify:all", "-cp", root.path + ":" + stdlib.path, "Driver"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "name/name\n")
        }
    }
}
#endif
