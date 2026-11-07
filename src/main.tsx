import './app.css';
import {StrictMode} from 'react';
import {createRoot} from 'react-dom/client';
import {registerSW} from 'virtual:pwa-register';
import {Theme} from '@astryxdesign/core/theme';
import {neutralTheme} from '@astryxdesign/theme-neutral/built';
import {App} from './App';
import {requestPersistence} from './data/db';

registerSW({immediate: true});
// 홈 화면에 추가된 앱이면 대부분 바로 허락된다
void requestPersistence();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Theme theme={neutralTheme} mode="system">
      <App />
    </Theme>
  </StrictMode>,
);
