#if canImport(Testing)
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func legacyJvmReferenceSubclassesCanUseTheirBoundReceiver() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            import kotlin.jvm.internal.FunctionReference;
            import kotlin.jvm.internal.MutablePropertyReference0;
            import kotlin.jvm.internal.Reflection;
            import kotlin.reflect.KDeclarationContainer;

            public class Driver {
                static final class Function extends FunctionReference {
                    Function(String value) { super(0, value); }
                    public KDeclarationContainer getOwner() {
                        return Reflection.getOrCreateKotlinClass(String.class);
                    }
                    public String getName() { return "length"; }
                    public String getSignature() { return "length()I"; }
                    Object invoke() { return ((String) receiver).length(); }
                }

                static final class Property extends MutablePropertyReference0 {
                    Property(StringBuilder value) { super(value); }
                    public Object get() { return receiver.toString(); }
                    public void set(Object value) {
                        StringBuilder builder = (StringBuilder) receiver;
                        builder.setLength(0);
                        builder.append(value);
                    }
                }

                public static void main(String[] args) {
                    Function function = new Function("kaigi");
                    if (function.getArity() != 0 || Reflection.function(function) != function) {
                        throw new AssertionError();
                    }
                    System.out.println(function.invoke());
                    Property reference = new Property(new StringBuilder());
                    Reflection.mutableProperty0(reference).set("ready");
                    System.out.println(Reflection.property0(reference).get());
                }
            }
            """.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            let compile = try jvmTool("javac", ["-cp", stdlib.path, "Driver.java"], root: root)
            try #require(compile.exitCode == 0, "\(compile.stderr)")
            let result = try java(["-Xverify:all", "-cp", root.path + ":" + stdlib.path, "Driver"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "5\nready\n")
        }
    }
}
#endif
