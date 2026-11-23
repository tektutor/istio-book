package org.tektutor.springshop.catalog;

import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

/** Answers product queries, and names the pod that answered. */
@SpringBootApplication
@RestController
public class CatalogApplication {

    @Value("${POD_NAME:local}")
    private String pod;

    public static void main(String[] args) {
        SpringApplication.run(CatalogApplication.class, args);
    }

    @GetMapping("/api/products/{id}")
    public Map<String, String> product(@PathVariable String id) {
        return Map.of("id", id, "name", "Product " + id, "pod", pod);
    }
}
