#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func javaCollectionSizeProperty(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = #"""
            import java.util.ArrayDeque
            import java.util.LinkedList
            import java.util.PriorityQueue
            import java.util.Queue

            fun main() {
                val eventQueue: Queue<Int> = ArrayDeque<Int>()
                eventQueue.offer(1)
                eventQueue.offer(2)
                println(eventQueue.size)

                val deque = ArrayDeque<Int>()
                deque.offer(3)
                println(deque.size)

                val linked = LinkedList<Int>()
                linked.add(4)
                println(linked.size)

                val heap = PriorityQueue<Int>()
                heap.offer(5)
                println(heap.size)
            }
            """#
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let run = try java(mode == .jvmJar ? ["-jar", output] : ["-cp", output, "HelloKt"])
            #expect(run.stdout == "2\n1\n1\n1\n")
            #expect(run.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func javaCollectionSizePropertyCustomImplementation(mode: EmitMode) throws {
        try withWorkspace { root in
            let javaSource = """
            package dep;
            import java.util.ArrayList;
            import java.util.Collection;
            import java.util.Iterator;
            import java.util.List;
            public class Events implements Collection<Object> {
                private final List<Object> backing = new ArrayList<Object>();
                @Override public int size() { return backing.size() + 100; }
                @Override public boolean isEmpty() { return backing.isEmpty(); }
                @Override public boolean contains(Object o) { return backing.contains(o); }
                @Override public Iterator<Object> iterator() { return backing.iterator(); }
                @Override public Object[] toArray() { return backing.toArray(); }
                @Override public <T> T[] toArray(T[] a) { return backing.toArray(a); }
                @Override public boolean add(Object o) { return backing.add(o); }
                @Override public boolean remove(Object o) { return backing.remove(o); }
                @Override public boolean containsAll(Collection<?> c) { return backing.containsAll(c); }
                @Override public boolean addAll(Collection<?> c) { return backing.addAll(c); }
                @Override public boolean removeAll(Collection<?> c) { return backing.removeAll(c); }
                @Override public boolean retainAll(Collection<?> c) { return backing.retainAll(c); }
                @Override public void clear() { backing.clear(); }
            }
            """
            try javaSource.write(to: root.appendingPathComponent("Events.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-d", "deps", "Events.java"], root: root)
            _ = try jvmTool("jar", ["cf", "deps.jar", "-C", "deps", "."], root: root)

            let source = """
            import dep.Events
            fun main() {
                val q = Events()
                q.add("x")
                println(q.size)
            }
            """
            let classpath = mode == .jvmJar ? root.appendingPathComponent("deps.jar").path : root.appendingPathComponent("deps").path
            let result = try compile(source, root: root, mode: mode, classpath: [classpath])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let run = try java(["-cp", output + ":" + classpath, "HelloKt"])
            #expect(run.stdout == "101\n")
            #expect(run.stderr.isEmpty)
        }
    }
}
#endif
