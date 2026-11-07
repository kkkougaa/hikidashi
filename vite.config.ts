import {defineConfig} from 'vitest/config';
import react from '@vitejs/plugin-react';
import {VitePWA} from 'vite-plugin-pwa';

// base './' 로 두면 GitHub Pages 같은 하위 경로에 올려도 그대로 동작함
export default defineConfig({
  base: './',
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icons/apple-touch-icon.png', 'icons/favicon.svg'],
      manifest: {
        name: 'hikidashi',
        short_name: 'hikidashi',
        description: '링크와 메모를 모아두는 나만의 서랍',
        lang: 'ko',
        start_url: './',
        scope: './',
        display: 'standalone',
        orientation: 'portrait',
        background_color: '#FFFFFF',
        theme_color: '#E6F0FB',
        icons: [
          {src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png'},
          {src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png'},
          {src: 'icons/icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable'},
        ],
        // 안드로이드 공유 메뉴에서 "hikidashi"로 바로 보내기
        share_target: {action: './', method: 'GET', params: {title: 'title', text: 'text', url: 'url'}},
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,png,svg,woff2}'],
        maximumFileSizeToCacheInBytes: 4 * 1024 * 1024,
        runtimeCaching: [
          {
            urlPattern: ({url}) => url.origin === 'https://fonts.googleapis.com' || url.origin === 'https://fonts.gstatic.com',
            handler: 'StaleWhileRevalidate',
            options: {cacheName: 'google-fonts', expiration: {maxEntries: 30, maxAgeSeconds: 60 * 60 * 24 * 365}},
          },
        ],
      },
    }),
  ],
  test: {environment: 'jsdom', setupFiles: ['src/test-setup.ts']},
});
