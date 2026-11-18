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
}
#endif
