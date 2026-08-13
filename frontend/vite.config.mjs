import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// During `npm run dev` the app calls the API with relative paths, so every
// backend route has to be proxied through the dev server. The target is
// localhost because the backend is reached from the host — either run directly
// or via the port published by docker-compose.
const backendTarget = process.env.VITE_DEV_PROXY_TARGET || 'http://localhost:8000'

const proxyBackend = {
  target: backendTarget,
  changeOrigin: true
}

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      '/game': proxyBackend,
      '/leaderboard': proxyBackend,
      '/health': proxyBackend
    }
  }
})
