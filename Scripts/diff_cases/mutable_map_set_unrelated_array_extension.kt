data class Point(val x:Int,val y:Int)
operator fun Array<CharArray>.set(at:Point,c:Char){this[at.y][at.x]=c}
fun main(){val values=mutableMapOf<Point,Int>();values[Point(0,0)]=1;println(values.values)}
