/*
 * KUU-3052: java.util.LinkedList Queue/Deque member coverage.
 * peek/poll/element/pop/offer/offerFirst/offerLast/peekFirst/pollLast/
 * getFirst/getLast/remove()/removeLast/removeFirstOccurrence/
 * removeLastOccurrence and descendingIterator are java.util.LinkedList
 * members on JVM; this case pins their resolution and the empty-list
 * NoSuchElementException contract (null messages on Kotlin/JVM).
 * println on the list itself additionally pins the toString/equals/hashCode
 * forwarding that Any members require outside the MutableList delegation.
 *
 * Expected stdout:
 * 0
 * 0
 * 0
 * [1, 2]
 * 9
 * true
 * true
 * true
 * [-1, 1, 2, 3, 4]
 * -1,4
 * -1,4
 * [1, 2, 3]
 * 1
 * 3
 * 1
 * 3
 * 1
 * 3
 * 1
 * [2, 3]
 * 3
 * [2]
 * true
 * [1, 3, 2, 1]
 * true
 * [1, 3, 1]
 * false
 * false
 * false
 * [1, 3, 1]
 * [1, 3, 1, 5]
 * null,null,null,null,null,null
 * element:null
 * pop:null
 * remove:null
 * getFirst:null
 * getLast:null
 * removeFirst:null
 * removeLast:null
 * true
 * [7]
 * true
 * false
 * true
 * false
 * true
 * true
 * false
 * 1
 * true
 * false
 * [9, 2]
 */

import java.util.LinkedList

fun main() {
    val ll = LinkedList<Int>()
    ll.add(1); ll.addFirst(0); ll.addLast(2)
    val p1: Int? = ll.peek(); println(p1)
    println(ll.element())
    val p2: Int? = ll.poll(); println(p2)
    println(ll)
    ll.push(9)
    println(ll.pop())
    println(ll.offer(3))
    println(ll.offerFirst(-1))
    println(ll.offerLast(4))
    println(ll)
    val pk1: Int? = ll.peekFirst(); val pk2: Int? = ll.peekLast(); println("$pk1,$pk2")
    val po1: Int? = ll.pollFirst(); val po2: Int? = ll.pollLast(); println("$po1,$po2")
    println(ll)
    println(ll.getFirst()); println(ll.getLast())
    println(ll.first); println(ll.last)
    println(ll.first()); println(ll.last())
    println(ll.remove()); println(ll)
    println(ll.removeLast()); println(ll)

    val d = LinkedList<Int>(); d.addAll(listOf(1, 2, 3, 2, 1))
    println(d.removeFirstOccurrence(2)); println(d)
    println(d.removeLastOccurrence(2)); println(d)
    println(d.removeFirstOccurrence(9)); println(d.removeLastOccurrence(9))
    println(d.removeFirstOccurrence("x"))
    val rev = mutableListOf<Int>(); val it = d.descendingIterator()
    while (it.hasNext()) rev.add(it.next())
    println(rev)
    d.add(5); d.add(6); val it2 = d.descendingIterator(); it2.next(); it2.remove(); println(d)

    val e = LinkedList<Int>()
    val q1: Int? = e.peek(); val q2: Int? = e.poll()
    val q3: Int? = e.peekFirst(); val q4: Int? = e.peekLast()
    val q5: Int? = e.pollFirst(); val q6: Int? = e.pollLast()
    println("$q1,$q2,$q3,$q4,$q5,$q6")
    try { e.element() } catch (x: NoSuchElementException) { println("element:${x.message}") }
    try { e.pop() } catch (x: NoSuchElementException) { println("pop:${x.message}") }
    try { e.remove() } catch (x: NoSuchElementException) { println("remove:${x.message}") }
    try { e.getFirst() } catch (x: NoSuchElementException) { println("getFirst:${x.message}") }
    try { e.getLast() } catch (x: NoSuchElementException) { println("getLast:${x.message}") }
    try { e.removeFirst() } catch (x: NoSuchElementException) { println("removeFirst:${x.message}") }
    try { e.removeLast() } catch (x: NoSuchElementException) { println("removeLast:${x.message}") }
    println(e.offer(7)); println(e)
    equalsProbe()

    // Indexed/membership operators resolve on JVM via LinkedList's operator
    // members (KUU-3260 covers the delegate-synthesized `operator` loss).
    val ops = LinkedList<Int>(); ops.add(1); ops.add(2)
    println(ops[0]); println(1 in ops); println(3 in ops)
    ops[0] = 9; println(ops)
}

private fun equalsProbe() {
    val a = LinkedList<Int>(); a.addAll(listOf(1, 2, 3))
    val b = LinkedList<Int>(); b.addAll(listOf(1, 2, 3))
    val c = LinkedList<Int>(); c.addAll(listOf(1, 2))
    println(a == b); println(a == c); println(a.equals(b)); println(a.equals(null))
    println(a.hashCode() == b.hashCode())
    println(a == listOf(1, 2, 3)); println(a == linkedMapOf(1 to 2))
}
