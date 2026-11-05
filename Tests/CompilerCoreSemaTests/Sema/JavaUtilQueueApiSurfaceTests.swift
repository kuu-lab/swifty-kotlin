@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

/// KUU-3996: bundled java.util.Queue/ArrayDeque/PriorityQueue API surface —
/// Queue-typed receivers over the FIFO shims, the Queue.remove() head
/// operation, and the PriorityQueue Collection/PriorityQueue/SortedSet
/// constructors. End-to-end heap ordering is pinned by the
/// kuu_3996_javautil_queue_surface diff case; these tests pin the
/// compile-time surface (the KSWIFTK-TYPE-0001 / SEMA-0002 diagnostics the
/// ticket reported).
@Suite
struct JavaUtilQueueApiSurfaceTests {
    @Test
    func queueTypedReceiversAcceptFifoShims() throws {
        let context = makeContextFromSource("""
        import java.util.Queue
        import java.util.ArrayDeque
        import java.util.LinkedList
        import java.util.PriorityQueue
        import java.util.concurrent.ConcurrentLinkedQueue

        fun drain(q: Queue<Int>) {
            while (!q.isEmpty()) {
                val head = q.remove()
                q.offer(head)
            }
        }

        fun main() {
            val deque: Queue<Int> = ArrayDeque<Int>()
            deque.offer(1)
            println(deque.element())
            println(deque.peek())
            println(deque.poll())
            println(deque.remove())
            drain(deque)

            val list: Queue<String> = LinkedList<String>()
            list.offer("a")
            println(list.element())
            println(list.poll())
            println(list.remove())

            val heap: Queue<Int> = PriorityQueue<Int>()
            heap.offer(2)
            println(heap.element())
            println(heap.poll())
            println(heap.remove())

            val clq: Queue<Int> = ConcurrentLinkedQueue<Int>()
            clq.offer(3)
            println(clq.element())
            println(clq.poll())
            println(clq.remove())
        }
        """)
        do { try runSema(context) } catch {}
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test
    func priorityQueueCollectionConstructorsResolve() throws {
        let context = makeContextFromSource("""
        import java.util.PriorityQueue
        import java.util.TreeSet

        fun main() {
            val natural = PriorityQueue(listOf(3, 1, 2))
            println(natural.poll())

            val typed = PriorityQueue<Int>(listOf(4, 0))
            println(typed.element())

            val source = PriorityQueue<Int>()
            source.offer(5)
            val copied = PriorityQueue(source)
            println(copied.poll())

            val sorted = TreeSet<Int>()
            sorted.add(6)
            val fromSet = PriorityQueue(sorted)
            println(fromSet.poll())

            // SortedSet/PriorityQueue arguments keep their ordering even
            // through a Collection-typed reference (JDK instanceof
            // dispatch inside the Collection constructor).
            val erasedSet: Collection<Int> = sorted
            val fromErasedSet = PriorityQueue(erasedSet)
            println(fromErasedSet.poll())
            val erasedQueue: Collection<Int> = source
            val fromErasedQueue = PriorityQueue(erasedQueue)
            println(fromErasedQueue.poll())
        }
        """)
        do { try runSema(context) } catch {}
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }
}
