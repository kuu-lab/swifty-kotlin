package fixture;
import java.util.*;
public final class ElementAccessOracle {
    public static Object list(boolean empty, boolean failGet) {
        return new AbstractList<Integer>() {
            public int size() { System.out.println("size"); return empty ? 0 : 2; }
            public boolean isEmpty() { System.out.println("empty"); return empty; }
            public Integer get(int index) {
                System.out.println("get:" + index);
                if (failGet) throw new IllegalStateException("get");
                return index == 0 ? 10 : 20;
            }
            public Iterator<Integer> iterator() { throw new AssertionError("list iterator"); }
        };
    }
    public static Object iterable(int count, int failure) {
        return new Iterable<Integer>() {
            boolean opened;
            public Iterator<Integer> iterator() {
                System.out.println("iterator");
                if (opened) throw new AssertionError("second iterator");
                opened = true;
                return new Iterator<Integer>() {
                    int index;
                    public boolean hasNext() {
                        System.out.println("has:" + index);
                        if (failure == 1) throw new IllegalStateException("has");
                        return index < count;
                    }
                    public Integer next() {
                        System.out.println("next:" + index);
                        if (failure == 2) throw new IllegalStateException("next");
                        return ++index;
                    }
                };
            }
        };
    }
    public static Object nullableIterable() {
        return (Iterable<String>) () -> Arrays.asList(null, "middle", null).iterator();
    }
    public static Object collection() {
        return new AbstractCollection<Integer>() {
            public int size() { throw new AssertionError("collection size"); }
            public boolean isEmpty() { throw new AssertionError("collection empty"); }
            public Iterator<Integer> iterator() { return Arrays.asList(7, 8).iterator(); }
        };
    }
}
