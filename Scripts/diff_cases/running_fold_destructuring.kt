// KUU-1894: preserve the second lambda parameter's Pair components.
data class Point(val x:Int){operator fun plus(p:Point)=Point(x+p.x);operator fun times(n:Int)=Point(x*n)}
fun main(){println(listOf(Point(2) to 3).runningFold(Point(0)){acc,(direction,distance)->acc+direction*distance}.last().x)}
