import React from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';

// Pinned to the 1.1.0 release tag rather than /releases/latest, so the download
// button cannot silently start serving a different build after the next release.
const downloads = {
  windows: 'https://github.com/mystrdan/Capsi/releases/download/1.1.0/Capsi-1.1.0-x64.msi',
  android: 'https://github.com/mystrdan/Capsi/releases/download/1.1.0/app-release.apk'
};

function detectPlatform() {
  if (typeof navigator === 'undefined') return null;
  const ua = navigator.userAgent || '';
  if (/Android/i.test(ua)) return 'android';
  if (/Windows/i.test(ua)) return 'windows';
  return null;
}
// Served from this origin (Website/public) instead of raw.githubusercontent.com: the
// icons are then covered by the same deploy as the page, and the site still renders
// its logo when GitHub is slow, blocked, or the default branch moves.
const logoUrl = '/capsi-logo-512.png';

const icons = {
  nearby: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><circle cx="12" cy="12" r="2.2"/><circle cx="12" cy="12" r="6"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/></svg>,
  messages: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M5 5.5h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H11l-4.5 3v-3H5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2Z"/><path d="M7 10h10M7 13h6"/></svg>,
  files: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M6 3h8l4 4v14H6z"/><path d="M14 3v5h5M9 12h6M9 16h6"/></svg>,
  trusted: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M12 3 20 6v5.5c0 4.8-3.1 7.8-8 9.5-4.9-1.7-8-4.7-8-9.5V6z"/><path d="m8.5 12 2.2 2.2 4.8-5"/></svg>,
  offline: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M5 7h14M5 12h10M5 17h7"/><path d="M17 14v6M14 17l3 3 3-3"/></svg>,
  direct: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="7" width="6" height="10" rx="1.5"/><rect x="15" y="7" width="6" height="10" rx="1.5"/><path d="M9 10h6M15 14H9M13 8l2 2-2 2M11 12l-2 2 2 2"/></svg>,
  pdf: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M6 3h8l4 4v14H6z"/><path d="M14 3v5h5"/><path d="M8.5 17.5v-5h1.8a1.4 1.4 0 0 1 0 2.8H8.5M13.5 12.5v5h1.2a2.5 2.5 0 0 0 0-5z"/></svg>,
  x: <svg viewBox="0 0 24 24" fill="currentColor"><path d="M18.9 2H22l-6.77 7.74L23.2 22h-6.24l-4.89-6.39L6.48 22H3.36l7.24-8.28L2.8 2h6.4l4.42 5.84L18.9 2Zm-1.1 17.9h1.73L8.27 3.98H6.42L17.8 19.9Z"/></svg>
};

// In-page navigation uses real anchor links rather than buttons, so they are
// keyboard reachable, announced as links, and work with in-page search. The
// smooth scroll is a progressive enhancement via CSS (scroll-behavior), not a
// scripted handler that would swallow the default navigation.
const sections = [
  { id: 'how', label: 'How it works' },
  { id: 'features', label: 'Features' },
  { id: 'files', label: 'Files' },
  { id: 'workplace', label: 'Workplace' },
];

function App() {
  const platform = detectPlatform();
  const primaryDownload =
    platform === 'android' ? downloads.android :
    platform === 'windows' ? downloads.windows :
    '/download';
  const primaryLabel =
    platform === 'android' ? 'Get Capsi for Android' :
    platform === 'windows' ? 'Download for Windows' :
    'Get Capsi';

  return (
    <div className="site">
      <header className="nav">
        <a className="brand" href="/" aria-label="Capsi home"><img src={logoUrl} alt="" /><span>CAPSI</span></a>
        <nav aria-label="Sections">
          {sections.map((section) => (
            <a key={section.id} href={`#${section.id}`}>{section.label}</a>
          ))}
          <a className="button small" href="/download">Get Capsi</a>
        </nav>
      </header>

      <main>
        <section className="hero">
          <div className="hero-copy">
            <div className="eyebrow">CAPSI</div>
            <h1>Run it.<br />Find devices.<br />Send.</h1>
            <h2>Messages and files, device to device.</h2>
            <p>Send messages and files directly between your devices. Capsi connects nearby devices over your local network &mdash; no account, cloud service, or internet connection required.</p>
            <div className="facts"><span>Device to device</span><span>No account</span><span>No cloud</span><span>Windows &amp; Android</span></div>
            <div className="actions"><a className="button" href={primaryDownload}>{primaryLabel}</a><a className="button outline" href="#how">See how it works</a></div>
            <small>Windows &middot; Android &middot; Available now &middot; Free to download and use</small>
          </div>
          <AppPreview />
        </section>

        <section className="statement">
          <div className="statement-mark"><img src={logoUrl} alt="" /></div>
          <div><div className="eyebrow">THE IDEA</div><h2>Why send it through the cloud when the devices are already right there?</h2></div>
          <p>Capsi is built for direct communication between devices around you. Connect over LAN, Wi-Fi or a hotspot and send messages and files without depending on a Capsi cloud service.</p>
        </section>

        <section id="how" className="dark-section">
          <div className="container">
            <div className="eyebrow">HOW IT WORKS</div>
            <h2>Run, find, connect, send.</h2>
            <div className="steps">
              <Step n="01" title="Run" text="Open Capsi on the devices you want to connect." />
              <Step n="02" title="Find" text="Capsi discovers reachable devices on your local network." />
              <Step n="03" title="Connect" text="Choose a device and establish a trusted connection." />
              <Step n="04" title="Send" text="Message or send files directly between the devices." />
            </div>
          </div>
        </section>

        <section id="features" className="features container">
          <div className="eyebrow">FEATURES</div>
          <h2>The useful parts, without the extra noise.</h2>
          <div className="feature-grid">
            <Feature icon={icons.nearby} title="Nearby devices" text="Find reachable Capsi devices on your local network without entering IP addresses manually." />
            <Feature icon={icons.messages} title="Messages" text="Send direct one-to-one messages and keep your conversation history on your device." />
            <Feature icon={icons.files} title="Files" text="Send files directly with progress and integrity checks, then open the finished file from the conversation." />
            <Feature icon={icons.trusted} title="Trusted devices" text="Choose which devices you trust, and remove one from your trusted list whenever you want." />
            <Feature icon={icons.offline} title="Offline" text="Keep communicating on the local network even when there is no internet connection." />
            <Feature icon={icons.direct} title="Direct" text="Messages and files move directly between connected devices - not through a Capsi cloud." />
          </div>
        </section>

        <section id="files" className="split filesexperience">
          <div>
            <div className="eyebrow">FILES</div>
            <h2>Send a file. Know what happened. Open it when it's there.</h2>
            <p>Each transfer appears as a file card in the conversation, showing the name, its type and size, and whether it is sending, receiving or finished.</p>
            <div className="filelist">
              <span><b>Type and size</b>Inferred from the file itself</span>
              <span><b>Status</b>Sent, received, failed or cancelled</span>
              <span><b>Image thumbnails</b>Shown where the format supports it</span>
              <span><b>Integrity</b>Every transfer is checked before it completes</span>
            </div>
          </div>
          <div className="filethread">
            <div className="bubble in"><b>Alex</b><span>Hey, here's the document.</span></div>
            <div className="filecard">
              <span className="fc-icon" aria-hidden="true">{icons.pdf}</span>
              <div className="fc-body">
                <strong>Project-Report.pdf</strong>
                <span>PDF &middot; 2.4 MB</span>
                <span className="fc-status">Received &middot; Available</span>
              </div>
              <span className="fc-action">Open</span>
            </div>
            <p className="file-note">On Windows you can also show the file in its folder. On Android it opens in an app that handles that type.</p>
          </div>
        </section>

        <section id="workplace" className="workplace">
          <div className="container workplace-layout">
            <div className="workplace-copy">
              <div className="eyebrow">WORKPLACE</div>
              <h2>More than device-to-device transfers.</h2>
              <p>For teams working on the same local network, Capsi can also organize trusted devices into a shared workplace with people, groups, departments and announcements.</p>
              <div className="workplace-list"><span>People &amp; roles</span><span>Groups</span><span>Departments</span><span>Announcements</span><span>Conversations</span><span>Local communication</span></div>
            </div>
            <div className="workplace-card">
              <div className="mini-header"><img src={logoUrl} alt="" /><strong>Workplace</strong><span>Local</span></div>
              <div className="mini-row"><b>People</b><span>12</span></div>
              <div className="mini-row"><b>Groups</b><span>4</span></div>
              <div className="mini-row"><b>Departments</b><span>3</span></div>
              <div className="mini-row"><b>Announcements</b><span>8</span></div>
              <div className="mini-note">For trusted devices on your local network</div>
            </div>
          </div>
        </section>

        <section className="split security">
          <div><div className="eyebrow">LOCAL FIRST</div><h2>Your devices. Your network. Your data.</h2></div>
          <div>
            <p>Capsi doesn't require an account or a Capsi cloud to move messages and files between connected devices.</p>
            <div className="security-points"><span><b>01</b> No account</span><span><b>02</b> No cloud</span><span><b>03</b> Direct</span><span><b>04</b> Encrypted</span></div>
          </div>
        </section>

        <section className="platforms container">
          <div className="eyebrow">PLATFORMS</div>
          <h2>Capsi, where you need it.</h2>
          <p className="section-lead">Capsi is available now for Windows and Android. More platforms will follow.</p>
          <div className="platform-grid">
            <Platform name="Windows" status="Available now - 10/11 64-bit" />
            <Platform name="Android" status="Available now - 7.0+" />
          </div>
        </section>

        <section className="download">
          <img className="download-logo" src={logoUrl} alt="Capsi" />
          <div className="eyebrow">GET CAPSI</div>
          <h2>Start sending.</h2>
          <p>Download Capsi for Windows or Android and connect your devices directly.</p>
          <a className="button" href={primaryDownload}>{primaryLabel}</a>
          <small>Windows 10/11 - 64-bit &nbsp;&mdash;&nbsp; Android 7.0+ - APK</small>
        </section>
      </main>

      <footer>
        <div className="footer-main"><div className="footer-brand"><img src={logoUrl} alt="" /><strong>CAPSI</strong></div><span>Messages and files, device to device.</span></div>
        <div className="footer-connect"><div className="footer-label">FOLLOW</div><div className="footer-links"><a href="https://x.com/runcapsi" target="_blank" rel="noreferrer" aria-label="Capsi on X"><span className="footer-icon">{icons.x}</span><span>@runcapsi</span></a></div></div>
        <span className="copyright">&copy; {new Date().getFullYear()} Capsi</span>
      </footer>
    </div>
  );
}

function Step({ n, title, text }) { return <article className="step"><span className="step-number">{n}</span><h3>{title}</h3><p>{text}</p></article>; }
function Feature({ icon, title, text }) { return <article className="feature"><div className="feature-icon">{icon}</div><h3>{title}</h3><p>{text}</p></article>; }

function Platform({ name, status }) {
  const logos = {
    Windows: <svg viewBox="0 0 24 24" aria-hidden="true" className="platform-svg"><path fill="currentColor" d="M2 4.5 10.5 3.3v8.2H2V4.5Zm9.8-1.35L22 1.7v9.8h-10.2V3.15ZM2 12.5h8.5v8.2L2 19.5v-7Zm9.8 0H22v9.8l-10.2-1.45V12.5Z" /></svg>,
    Android: <svg viewBox="0 0 24 24" aria-hidden="true" className="platform-svg"><path fill="currentColor" d="M7.1 7.4 5.55 4.72a.65.65 0 1 1 1.12-.65l1.53 2.64A8.2 8.2 0 0 1 12 5.8c1.35 0 2.63.32 3.76.9l1.57-2.63a.65.65 0 1 1 1.12.67L16.9 7.42A7.65 7.65 0 0 1 19.7 13v4.25c0 .96-.78 1.75-1.75 1.75h-.95v2.45a1.05 1.05 0 1 1-2.1 0V19h-5.8v2.45a1.05 1.05 0 1 1-2.1 0V19h-.95A1.75 1.75 0 0 1 4.3 17.25V13a7.65 7.65 0 0 1 2.8-5.6ZM8.1 11.1a.9.9 0 1 0 0-1.8.9.9 0 0 0 0 1.8Zm7.8 0a.9.9 0 1 0 0-1.8.9.9 0 0 0 0 1.8Z" /></svg>,
  };
  return <div className="platform"><span className="platform-icon">{logos[name]}</span><div><strong>{name}</strong><small>{status}</small></div></div>;
}

function AppPreview() {
  return <div className="app-preview">
    <div className="window-bar"><span className="window-logo"><img src={logoUrl} alt="" /></span><b>Capsi</b><span className="window-more">&bull;&bull;&bull;</span></div>
    <div className="preview-body">
      <aside>
        <div className="preview-nav active">Nearby</div>
        <div className="preview-nav">Messages</div>
        <div className="preview-nav">Files</div>
        <div className="preview-nav">Trusted devices</div>
        <div className="preview-nav">Workplace</div>
      </aside>
      <div className="preview-main">
        <div className="preview-title">Nearby devices</div>
        <div className="device-row"><span className="avatar">PC</span><div><b>Office PC</b><small>Ready to connect</small></div><span className="online">ONLINE</span></div>
        <div className="device-row"><span className="avatar">LP</span><div><b>My Laptop</b><small>Trusted device</small></div><span className="online">ONLINE</span></div>
        <div className="preview-empty"><img src={logoUrl} alt="" /><strong>Find a device. Start sending.</strong><span>Messages and files stay between connected devices.</span></div>
      </div>
    </div>
  </div>;
}

function DownloadPage() {
  return <div className="download-page">
    <div className="download-page-inner">
      <a className="brand" href="/" aria-label="Capsi home"><img src={logoUrl} alt="" /><span>CAPSI</span></a>
      <div className="eyebrow">GET CAPSI</div>
      <h1>Start sending.</h1>
      <p>Download Capsi for Windows or Android and connect your devices directly.</p>
      <div className="download-options">
        <DownloadOption name="Windows" description="Windows 10/11 - 64-bit" label="Download for Windows" href={downloads.windows} />
        <DownloadOption name="Android" description="Android 7.0+ - APK" label="Download for Android" href={downloads.android} />
      </div>
      <a className="back-link" href="/">&larr; Back to Capsi</a>
    </div>
  </div>;
}

function DownloadOption({ name, description, label, href }) {
  return <div className="download-option"><div><strong>{name}</strong><span>{description}</span></div><a className="button" href={href}>{label}</a></div>;
}

const root = createRoot(document.getElementById('root'));
root.render(window.location.pathname === '/download' ? <DownloadPage /> : <App />);
