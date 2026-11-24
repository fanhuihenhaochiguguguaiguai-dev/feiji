import { defineConfig } from 'vite';
export default defineConfig({
  base: './',
  define: { __FLAGSHIP_QA__: JSON.stringify(process.env.VITE_GAME_QA==='1') },
  build: {
    target: 'es2022',
    assetsInlineLimit: 0,
    chunkSizeWarningLimit: 1000,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('/@babylonjs/core/Maths/')) return 'flight-math';
        }
      }
    }
  }
});
