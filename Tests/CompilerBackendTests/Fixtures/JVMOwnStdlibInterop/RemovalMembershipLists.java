package fixture;

import java.util.ArrayList;

public final class RemovalMembershipLists {
    public static Object rhs(int size) {
        ArrayList<String> result = new ArrayList<>() {
            @Override
            public boolean contains(Object value) {
                System.out.println("contains:" + value);
                return super.contains(value);
            }
        };
        result.add("B");
        if (size > 1) result.add("x");
        if (size > 2) result.add("y");
        return result;
    }
}
