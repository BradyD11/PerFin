import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// In development the API is `ledger serve` on 8787; in production that same
// server serves this build from web/dist, so /api is always same-origin.
export default defineConfig({
  plugins: [react()],
  server: { proxy: { "/api": "http://localhost:8787" } },
});
