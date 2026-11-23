package org.tektutor.shop.cart;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import org.junit.jupiter.api.Test;

/** Tests for the in-memory cart store. Run them with: mvn test */
class CartStoreTest {

    @Test
    void addedItemsStayInTheUsersCart() {
        CartStore store = new CartStore();
        store.add("kayal", new CartStore.Item("SKU-1", 2));
        store.add("kayal", new CartStore.Item("SKU-7", 1));
        assertEquals(List.of(new CartStore.Item("SKU-1", 2),
                             new CartStore.Item("SKU-7", 1)),
                     store.items("kayal"));
        assertTrue(store.items("prabhu").isEmpty());
    }

    @Test
    void clearEmptiesOneCart() {
        CartStore store = new CartStore();
        store.add("kayal", new CartStore.Item("SKU-1", 2));
        store.add("prabhu", new CartStore.Item("SKU-2", 1));
        store.clear("kayal");
        assertTrue(store.items("kayal").isEmpty());
        assertEquals(1, store.items("prabhu").size());
    }
}
