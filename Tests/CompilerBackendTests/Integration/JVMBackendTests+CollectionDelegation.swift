#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionDelegatesPreserveObjectClassAndErasedInterfaceDispatch(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            object Values : MutableList<Any> by mutableListOf()
            class ListWrapper<T>(delegate: MutableList<T>) : MutableList<T> by delegate
            class ReadOnlyList(delegate: List<Int>) : List<Int> by delegate
            class Offset(private val backing: List<Int>) : List<Int> by backing {
                override fun get(index: Int): Int = backing[index] + 100
                override val size: Int get() = backing.size + 100
            }
            class Adder(private val backing: MutableList<Int>): MutableList<Int> by backing {
                override fun add(element: Int): Boolean = backing.add(element + 100)
            }
            class Keys(backing: Map<String, Int>): Map<String, Int> by backing {
                override val keys: Set<String> get() = setOf("chosen")
            }
            class ArrayView(delegate: List<Int>) : List<Int> by delegate {
                override fun iterator(): Iterator<Int> = listOf(8, 9).iterator()
            }
            class EmptyView(delegate: List<Int>) : List<Int> by delegate {
                override val size: Int get() = 0
            }
            object Numbers : MutableSet<Int> by mutableSetOf(2, 4)
            object Counts : MutableMap<String, Int> by mutableMapOf("one" to 1)
            fun main() {
                println(Values.size)
                Values.add("one"); Values.add(2)
                val values: MutableList<Any> = Values
                println(values.size); println(values[0]); println(values.containsAll(listOf<Any>("one", 2)))
                println(values.removeAt(1)); println(values.size)
                val backing = mutableListOf(10, 20)
                val wrapper = ListWrapper(backing)
                println(wrapper[1]); println(wrapper.add(30))
                val list: MutableList<Int> = wrapper
                println(list.set(0, 11)); println(backing[0])
                val readOnly: List<Int> = ReadOnlyList(listOf(3, 5))
                println(readOnly.size); println(readOnly[1]); println(readOnly.contains(3))
                val set: MutableSet<Int> = Numbers
                println(set.add(6)); println(set.contains(6)); println(set.remove(2)); println(set.size)
                val map: MutableMap<String, Int> = Counts
                map["two"] = 2; println(map["two"]); println(map.containsKey("one")); println(map.size)
                val erased: Any = readOnly
                println(erased is MutableList<*>); println((Values as Any) is MutableList<*>)
                val overridden: List<Int> = Offset(listOf(4, 6)); println(overridden[1]); println(overridden.size)
                val adding: MutableList<Int> = Adder(mutableListOf()); println(adding.add(9)); println(adding[0])
                val keyed: Map<String, Int> = Keys(mapOf("one" to 1)); println(keyed.keys.contains("chosen"))
            }
            """
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-Xverify:all", "-cp", output.path + ":" + library.path, "HelloKt"])
            let expected = "0\n2\none\ntrue\n2\n1\n20\ntrue\n10\n11\n2\n5\ntrue\ntrue\ntrue\ntrue\n2\n2\ntrue\n2\nfalse\ntrue\n106\n102\ntrue\n109\ntrue\n"
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)
            _ = try jvmTool("kotlinc", ["hello.kt", "-d", "reference.jar"], root: root)
            let reference = root.appendingPathComponent("reference.jar")
            #expect(try java(["-Xverify:all", "-cp", reference.path + ":" + m11Runtime(), "HelloKt"]).stdout == expected)
            #expect(try java(["-Xverify:all", "-cp", reference.path + ":" + library.path, "HelloKt"]).stdout == expected)
            try """
            import java.util.*;
            public class CollectionConsumer {
                public static void main(String[] args) {
                    ReadOnlyList concrete = new ReadOnlyList(Arrays.asList(3, 5));
                    System.out.println(concrete.getSize());
                    List<Integer> values = concrete;
                    System.out.println(Arrays.toString(values.toArray(new Integer[0])));
                    System.out.println(values.containsAll(Arrays.asList(3, 5)));
                    System.out.println(values.contains("wrong")); System.out.println(values.indexOf("wrong"));
                    Iterator<Integer> iterator = concrete.iterator(); System.out.println(iterator.next());
                    System.out.println(concrete.containsAll(Arrays.asList("wrong")));
                    try { values.add(7); } catch (UnsupportedOperationException expected) { System.out.println(expected.getMessage()); }
                    try { values.sort(null); } catch (UnsupportedOperationException expected) { System.out.println("sort-blocked"); }
                    System.out.println(values.removeIf(value -> false));
                    List<Integer> emptyList = new ReadOnlyList(Collections.emptyList());
                    try { emptyList.removeFirst(); } catch (UnsupportedOperationException expected) { System.out.println("removeFirst-blocked"); }
                    Map<String, Integer> keys = new Keys(Collections.singletonMap("one", 1));
                    System.out.println(keys.keySet().contains("chosen"));
                    try { keys.putIfAbsent("one", 2); } catch (UnsupportedOperationException expected) { System.out.println("putIfAbsent-blocked"); }
                    List<Integer> mutable = new ListWrapper<Integer>(new ArrayList<Integer>(Arrays.asList(8, 9)));
                    mutable.add(10); System.out.println(mutable.remove(0)); System.out.println(mutable.size());
                    List<Integer> adding = new Adder(new ArrayList<Integer>(Arrays.asList(1, 2)));
                    System.out.println(adding.remove(0)); System.out.println(adding.remove(Integer.valueOf(2)));
                    ArrayView array = new ArrayView(Arrays.asList(1, 2));
                    Integer[] typed = array.toArray(new Integer[0]);
                    System.out.println(Arrays.toString(array.toArray())); System.out.println(Arrays.toString(typed));
                    EmptyView empty = new EmptyView(Arrays.asList(1, 2));
                    System.out.println(Arrays.toString(empty.toArray())); System.out.println(Arrays.toString(empty.toArray(new Integer[0])));
                    List<Integer> overridden = new Offset(Arrays.asList(4, 6));
                    System.out.println(overridden.get(1)); System.out.println(overridden.size());
                    Iterator<Integer> range = new kotlin.ranges.IntRange(1, 2).iterator();
                    System.out.println(range.next());
                }
            }
            """.write(to: root.appendingPathComponent("CollectionConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", output.path + ":" + library.path, "CollectionConsumer.java"], root: root)
            let consumer = try java(["-cp", root.path + ":" + output.path + ":" + library.path, "CollectionConsumer"])
            #expect(consumer.exitCode == 0)
            #expect(consumer.stdout == "2\n[3, 5]\ntrue\nfalse\n-1\n3\nfalse\nOperation is not supported for read-only collection\nsort-blocked\nfalse\nremoveFirst-blocked\ntrue\nputIfAbsent-blocked\n8\n2\n1\ntrue\n[8, 9]\n[8, 9]\n[]\n[]\n106\n102\n1\n")
            #expect(consumer.stderr.isEmpty)
            try """
            fun main() {
                val values = ListWrapper(mutableListOf(10, 20))
                println(values.removeAt(0)); println(values.size)
                println(ReadOnlyList(listOf(3, 5))[1])
                println(Offset(listOf(4, 6))[1])
                println(Keys(mapOf("one" to 1)).keys.contains("chosen"))
                println(ReadOnlyList(listOf(3, 5)).containsAll(listOf(3)))
                println(ReadOnlyList(listOf(3, 5)).iterator().next())
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", output.path + ":" + m11Runtime(), "-d", "consumer.jar"], root: root)
            let kotlinConsumer = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + output.path + ":" + library.path, "ConsumerKt"])
            #expect(kotlinConsumer.exitCode == 0)
            #expect(kotlinConsumer.stdout == "10\n1\n5\n106\ntrue\ntrue\n3\n")
            #expect(kotlinConsumer.stderr.isEmpty)


        }
    }
}
#endif
