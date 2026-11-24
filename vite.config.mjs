import { defineConfig } from 'vite';
import { readFileSync } from 'node:fs';
const release=JSON.parse(readFileSync(new URL('./package.json',import.meta.url),'utf8')).version;
export default defineConfig({
  base: './',
  define: { __FLAGSHIP_QA__: JSON.stringify(process.env.VITE_GAME_QA==='1'), __GAME_RELEASE__: JSON.stringify(release) },
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
