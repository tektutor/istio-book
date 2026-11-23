package org.tektutor.shop.cart;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import org.springframework.stereotype.Component;

/**
 * The carts of all users, kept in the memory of this pod only. A user
 * whose requests reach another pod sees an empty cart. Chapter 17 uses
 * this to show why consistent hashing matters.
 */
@Component
public class CartStore {

    /** One line of a cart. */
    public record Item(String sku, int quantity) {}

    private final Map<String, List<Item>> carts = new ConcurrentHashMap<>();

    public List<Item> items(String user) {
        return List.copyOf(carts.getOrDefault(user, List.of()));
    }

    public List<Item> add(String user, Item item) {
        carts.computeIfAbsent(user, u -> new CopyOnWriteArrayList<>())
             .add(item);
        return items(user);
    }

    public void clear(String user) {
        carts.remove(user);
    }
}
