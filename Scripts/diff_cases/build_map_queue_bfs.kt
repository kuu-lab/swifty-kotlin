// KUU-1912: buildMap must retain its expected types across apply and destructured let.
data class Point(val x:Int,val y:Int)
fun map():Map<Point,Int> = buildMap {val queue=ArrayDeque<Pair<Point,Int>>().apply {add(Point(0,0) to 0)};while(queue.isNotEmpty()){queue.removeFirst().let {(location,distance)->if(location !in this){this[location]=distance}}}}
fun main(){println(map().values)}
