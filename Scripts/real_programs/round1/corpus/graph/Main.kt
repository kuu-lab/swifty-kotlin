import structures.*
fun main() {
    val graph = Graph<Int>()
    for (v in 1..4) graph.addVertex(v)
    graph.addEdge(1, 2)
    graph.addEdge(1, 3)
    graph.addEdge(2, 4)
    println(graph.connectedVertexes(1).joinToString(","))
    println(graph.breadthFirstTraversal().joinToString(","))
}
