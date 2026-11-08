import './app.css';
import {StrictMode} from 'react';
import {createRoot} from 'react-dom/client';
import {registerSW} from 'virtual:pwa-register';
import {Theme} from '@astryxdesign/core/theme';
import {neutralTheme} from '@astryxdesign/theme-neutral/built';
import {App} from './App';
import {requestPersistence} from './data/db';
import {usePref} from './lib/prefs';

registerSW({immediate: true});
// 홈 화면에 추가된 앱이면 대부분 바로 허락된다
void requestPersistence();

/** 설정의 화면 모드(시스템·라이트·다크)를 따른다 */
function Root() {
  const [theme] = usePref('theme');
  return (
    <Theme theme={neutralTheme} mode={theme}>
      <App />
    </Theme>
  );
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Root />
  </StrictMode>,
);
