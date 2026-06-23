import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    proxy: {
      '/api': {
        target: 'https://wsyufu.net',
        changeOrigin: true,
      },
      '/auth': {
        target: 'https://wsyufu.net',
        changeOrigin: true,
      },
    },
  },
})
