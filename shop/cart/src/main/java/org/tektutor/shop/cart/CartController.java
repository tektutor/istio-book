package org.tektutor.shop.cart;

import java.util.LinkedHashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * The cart API. Every answer names the pod that served it, so you can
 * see where the mesh sent each request.
 *
 *   GET    /api/cart/{user}          the user's cart
 *   POST   /api/cart/{user}/items    add {"sku": "...", "quantity": n}
 *   DELETE /api/cart/{user}          empty the cart
 */
@RestController
@RequestMapping("/api/cart")
public class CartController {

    private static final Logger log =
            LoggerFactory.getLogger(CartController.class);

    private final CartStore store;
    private final RestClient inventory;
    private final String pod;

    public CartController(CartStore store,
                          @Value("${inventory.url}") String inventoryUrl,
                          @Value("${POD_NAME:local}") String pod) {
        this.store = store;
        this.inventory = RestClient.builder().baseUrl(inventoryUrl).build();
        this.pod = pod;
    }

    @GetMapping("/{user}")
    public Map<String, Object> cart(@PathVariable String user) {
        log.info("GET /api/cart/{}", user);
        return answer(user);
    }

    @PostMapping("/{user}/items")
    public ResponseEntity<Map<String, Object>> add(
            @PathVariable String user, @RequestBody CartStore.Item item) {
        log.info("POST /api/cart/{}/items sku={} quantity={}",
                 user, item.sku(), item.quantity());
        Map<?, ?> stock;
        try {
            stock = inventory.get()
                    .uri("/api/stock/{sku}", item.sku())
                    .retrieve()
                    .body(Map.class);
        } catch (RestClientException e) {
            log.warn("inventory call failed: {}", e.getMessage());
            Map<String, Object> error = new LinkedHashMap<>();
            error.put("error", "inventory unavailable");
            error.put("pod", pod);
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(error);
        }
        int available = ((Number) stock.get("available")).intValue();
        if (item.quantity() > available) {
            Map<String, Object> error = answer(user);
            error.put("error", "only " + available + " in stock");
            return ResponseEntity.status(HttpStatus.CONFLICT).body(error);
        }
        store.add(user, item);
        return ResponseEntity.ok(answer(user));
    }

    @DeleteMapping("/{user}")
    public Map<String, Object> clear(@PathVariable String user) {
        log.info("DELETE /api/cart/{}", user);
        store.clear(user);
        return answer(user);
    }

    private Map<String, Object> answer(String user) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("user", user);
        body.put("items", store.items(user));
        body.put("pod", pod);
        return body;
    }
}
