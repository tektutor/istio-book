package org.tektutor.springshop.storefront;

import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.cloud.client.loadbalancer.LoadBalanced;
import org.springframework.context.annotation.Bean;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;

/** Shows a product page: it asks the catalog for the product. */
@SpringBootApplication
@RestController
public class StorefrontApplication {

    @Value("${POD_NAME:local}")
    private String pod;

    private final RestClient catalog;

    public StorefrontApplication(RestClient.Builder builder,
                                 @Value("${catalog.url}") String url) {
        this.catalog = builder.baseUrl(url).build();
    }

    public static void main(String[] args) {
        SpringApplication.run(StorefrontApplication.class, args);
    }

    /** Step 1: Spring Cloud LoadBalancer asks Eureka for the catalog's
     *  pods and sends each request to one pod address. */
    @Bean
    @LoadBalanced
    @ConditionalOnProperty(name = "storefront.discovery",
                           havingValue = "true", matchIfMissing = true)
    static RestClient.Builder loadBalancedBuilder() {
        return RestClient.builder();
    }

    /** Step 2: a plain client. The URL names the Kubernetes Service, and
     *  the sidecar routes, balances and encrypts the request. */
    @Bean
    @ConditionalOnProperty(name = "storefront.discovery",
                           havingValue = "false")
    static RestClient.Builder plainBuilder() {
        return RestClient.builder();
    }

    @GetMapping("/api/shop/{id}")
    public Map<String, Object> page(@PathVariable String id) {
        Map<?, ?> product = catalog.get().uri("/api/products/{id}", id)
                .retrieve().body(Map.class);
        return Map.of("product", product, "storefront", pod);
    }
}
