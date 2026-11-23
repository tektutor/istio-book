// The TekTutor Shop frontend, version 1.1: version 1.0 with one span for
// each click. It calls the cart API on the same host, or on
// VITE_API_BASE when you set it, for example while you develop.
import { useEffect, useState } from "react";
import { tracer } from "./tracing.js";

const API = import.meta.env.VITE_API_BASE ?? "";
const PRODUCTS = [
  { sku: "SKU-1", name: "Istio in Practice, Volume 1" },
  { sku: "SKU-2", name: "Istio in Practice, Volume 2" },
  { sku: "SKU-7", name: "Lab notebook" },
];

export default function App() {
  const [user, setUser] = useState("kayal");
  const [cart, setCart] = useState({ items: [], pod: "" });
  const [message, setMessage] = useState("");

  function call(method, path, body) {
    const name = `${method} cart${path}`;
    return tracer.startActiveSpan(name, async (span) => {    // (1)
      try {
        const headers = { "x-shop-user": user };          // for Chapter 17
        if (body) headers["Content-Type"] = "application/json";
        const response = await fetch(`${API}/api/cart/${user}${path}`, {
          method,
          headers,
          body: body ? JSON.stringify(body) : undefined,
        });
        const data = await response.json();
        setMessage(response.ok ? "" : data.error ?? `error ${response.status}`);
        if (data.items) setCart(data);
        span.setAttribute("shop.user", user);
      } finally {
        span.end();                                          // (2)
      }
    });
  }

  useEffect(() => {
    call("GET", "").catch((e) => setMessage(e.message));
  }, [user]);

  return (
    <main>
      <h1>TekTutor Shop</h1>
      <label>
        User <input value={user} onChange={(e) => setUser(e.target.value)} />
      </label>
      <ul>
        {PRODUCTS.map((p) => (
          <li key={p.sku}>
            {p.name}{" "}
            <button onClick={() => call("POST", "/items",
                                         { sku: p.sku, quantity: 1 })}>
              Add
            </button>
          </li>
        ))}
      </ul>
      <h2>Cart</h2>
      <ul>
        {cart.items.map((item, i) => (
          <li key={i}>{item.sku} x {item.quantity}</li>
        ))}
      </ul>
      <button onClick={() => call("DELETE", "")}>Empty the cart</button>
      <p>Served by: {cart.pod}</p>
      {message && <p role="alert">{message}</p>}
    </main>
  );
}
