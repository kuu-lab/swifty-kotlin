#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionToArrayPreservesStoreOrderAndArrayIdentity(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = "class ArrayContract(delegate: List<Any>) : List<Any> by delegate"
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            _ = try jvmTool("kotlinc", ["hello.kt", "-d", "reference.jar"], root: root)
            try """
            import java.util.*;
            public class ArrayConsumer {
                static List<Object> backing(boolean bad, int reportedSize, StringBuilder trace) {
                    return new AbstractList<Object>() {
                        public int size() { return reportedSize; }
                        public Object get(int index) { throw new AssertionError(); }
                        public Iterator<Object> iterator() {
                            return new Iterator<Object>() {
                                int index;
                                public boolean hasNext() { trace.append("has "); return index < 2; }
                                public Object next() {
                                    index++; trace.append("next" + index + " ");
                                    if (bad) {
                                        if (index == 2) throw new IllegalStateException("later");
                                        return 42;
                                    }
                                    return index == 1 ? "one" : "two";
                                }
                            };
                        }
                    };
                }
                public static void main(String[] args) {
                    for (boolean bad : new boolean[] { true, false }) {
                        StringBuilder trace = new StringBuilder();
                        try {
                            String[] values = new ArrayContract(backing(bad, 2, trace)).toArray(new String[0]);
                            trace.append(Arrays.toString(values));
                        } catch (RuntimeException error) { trace.append(error.getClass().getSimpleName()); }
                        System.out.println(trace);
                    }
                    for (int reportedSize : new int[] { 1, 4 }) {
                        ArrayContract value = new ArrayContract(backing(false, reportedSize, new StringBuilder()));
                        System.out.println(Arrays.toString(value.toArray()));
                        System.out.println(Arrays.toString(value.toArray(new String[0])));
                        String[] supplied = { "a", "b", "c", "d", "e" };
                        System.out.println(value.toArray(supplied) == supplied);
                        System.out.println(Arrays.toString(supplied));
                    }
                    ArrayContract empty = new ArrayContract(Collections.emptyList());
                    System.out.println(empty.toArray() == empty.toArray());
                    String[] supplied = { "old", "tail" };
                    System.out.println(empty.toArray(supplied) == supplied);
                    System.out.println(Arrays.toString(supplied));
                    try { empty.toArray((String[]) null); }
                    catch (NullPointerException expected) { System.out.println("null-blocked"); }
                }
            }
            """.write(to: root.appendingPathComponent("ArrayConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", output.path + ":" + library.path, "ArrayConsumer.java"], root: root)
            let expected = "has next1 ArrayStoreException\nhas next1 has next2 has [one, two]\n[one, two]\n[one, two]\ntrue\n[one, two, null, d, e]\n[one, two]\n[one, two]\ntrue\n[one, two, null, d, e]\ntrue\ntrue\n[null, tail]\nnull-blocked\n"
            let reference = root.appendingPathComponent("reference.jar")
            let referenceRuntime = try m11Runtime()
            for classpath in [output.path + ":" + library.path,
                              reference.path + ":" + referenceRuntime,
                              reference.path + ":" + library.path] {
                let execution = try java(["-Xverify:all", "-cp", root.path + ":" + classpath, "ArrayConsumer"])
                #expect(execution.exitCode == 0)
                #expect(execution.stdout == expected)
                #expect(execution.stderr.isEmpty)
            }
        }
    }
}
#endif
