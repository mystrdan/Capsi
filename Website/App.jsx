import React from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';

const downloadUrl = 'https://github.com/mystrdan/Capsi/releases/latest/download/Capsi_1.0.2_x64-setup.exe';
const logoUrl = 'https://raw.githubusercontent.com/mystrdan/Capsi/main/Capsi/icons/capsi-logo-512.png';

const icons = {
  nearby: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><circle cx="12" cy="12" r="2.2"/><circle cx="12" cy="12" r="6"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/></svg>,
  messages: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M5 5.5h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H11l-4.5 3v-3H5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2Z"/><path d="M7 10h10M7 13h6"/></svg>,
  files: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M6 3h8l4 4v14H6z"/><path d="M14 3v5h5M9 12h6M9 16h6"/></svg>,
  trusted: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M12 3 20 6v5.5c0 4.8-3.1 7.8-8 9.5-4.9-1.7-8-4.7-8-9.5V6z"/><path d="m8.5 12 2.2 2.2 4.8-5"/></svg>,
  offline: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M5 7h14M5 12h10M5 17h7"/><path d="M17 14v6M14 17l3 3 3-3"/></svg>,
  direct: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="7" width="6" height="10" rx="1.5"/><rect x="15" y="7" width="6" height="10" rx="1.5"/><path d="M9 10h6M15 14H9M13 8l2 2-2 2M11 12l-2 2 2 2"/></svg>,
  x: <svg viewBox="0 0 24 24" fill="currentColor"><path d="M18.9 2H22l-6.77 7.74L23.2 22h-6.24l-4.89-6.39L6.48 22H3.36l7.24-8.28L2.8 2h6.4l4.42 5.84L18.9 2Zm-1.1 17.9h1.73L8.27 3.98H6.42L17.8 19.9Z"/></svg>,
  mail: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m4 7 8 6 8-6"/></svg>
};

function App() {
  const scrollTo = (id) => document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
  return (
    <div className="site">
      <header className="nav">
        <a className="brand" href="/" aria-label="Capsi home"><img src={logoUrl} alt="" /><span>CAPSI</span></a>
        <nav><button onClick={() => scrollTo('how')}>How it works</button><button onClick={() => scrollTo('features')}>Features</button><button onClick={() => scrollTo('workplace')}>WorkPlace</button><a className="button small" href={downloadUrl}>Download</a></nav>
      </header>
      <main>
        <section className="hero"><div className="hero-copy"><div className="eyebrow">CAPSI</div><h1>Run it.<br />Find devices.<br />Send.</h1><h2>Messages and files, device to device.</h2><p>Capsi is a lightweight communication utility for connected devices. Discover nearby Capsi devices, accept trusted peers, exchange messages and transfer files directly.</p><div className="facts"><span>Device to device</span><span>No account</span><span>No Capsi cloud</span><span>Local-first</span></div><div className="actions"><a className="button" href={downloadUrl}>Download Capsi</a><button className="button outline" onClick={() => scrollTo('how')}>See how it works</button></div><small>Windows 64-bit · Current release focus · Free to download and use</small></div><AppPreview /></section>
        <section className="statement"><div className="statement-mark"><img src={logoUrl} alt="" /></div><div><div className="eyebrow">THE IDEA</div><h2>Communication does not always need a middleman.</h2></div><p>When your devices can reach one another, Capsi lets them communicate directly. Wi-Fi, wired Ethernet, hotspot, or another supported local communication network — the product stays focused on the devices in front of you.</p></section>
        <section id="how" className="dark-section"><div className="container"><div className="eyebrow">SIMPLE BY DESIGN</div><h2>Run. Find. Send.</h2><div className="steps"><Step n="01" title="Run" text="Install Capsi and give your device a name. Your device identity stays local." /><Step n="02" title="Find" text="Capsi discovers other Capsi devices on the connected network." /><Step n="03" title="Trust" text="Accept a device before treating it as a trusted peer." /><Step n="04" title="Send" text="Exchange direct messages and offer files to another trusted device." /></div></div></section>
        <section id="features" className="features container"><div className="eyebrow">THE USEFUL PARTS</div><h2>Everything you need. Nothing that gets in the way.</h2><div className="feature-grid">
          <Feature icon={icons.nearby} title="Nearby" text="Discover other Capsi devices on your connected network without manually typing addresses." />
          <Feature icon={icons.messages} title="Messages" text="Keep direct one-to-one conversations between devices with local conversation history." />
          <Feature icon={icons.files} title="Files" text="Offer files directly, with acceptance, integrity checks, delivery handling and resumable transfers." />
          <Feature icon={icons.trusted} title="Trusted devices" text="Accept, block, rename or forget peers. New devices do not become trusted automatically." />
          <Feature icon={icons.offline} title="Offline delivery" text="Pending messages can remain local and retry when a recipient becomes reachable." />
          <Feature icon={icons.direct} title="Direct transport" text="Peer communication uses a signed handshake and encrypted transport rather than a Capsi cloud service." />
        </div></section>
        <section id="workplace" className="workplace"><div className="container workplace-layout"><div className="workplace-copy"><div className="eyebrow">OPTIONAL · WORKPLACE</div><h2>A workplace layer without a workplace server.</h2><p>WorkPlace adds structure for trusted Capsi devices while keeping the local-first model. Create people, groups and departments, assign roles and permissions, send broadcasts and have workplace conversations.</p><div className="workplace-list"><span>People & roles</span><span>Groups</span><span>Departments</span><span>Broadcasts</span><span>Workplace conversations</span><span>Direct synchronization</span></div></div><div className="workplace-card"><div className="mini-header"><img src={logoUrl} alt="" /><strong>WorkPlace</strong><span>Local</span></div><div className="mini-row"><b>People</b><span>12</span></div><div className="mini-row"><b>Groups</b><span>4</span></div><div className="mini-row"><b>Departments</b><span>3</span></div><div className="mini-row"><b>Broadcasts</b><span>8</span></div><div className="mini-note">Trusted devices · Direct synchronization</div></div></div></section>
        <section className="split security"><div><div className="eyebrow">LOCAL FIRST</div><h2>Your devices. Your network. Your data.</h2></div><div><p>Capsi does not require a central Capsi cloud service, account system or central workplace server for local communication.</p><div className="security-points"><span><b>01</b> No signup</span><span><b>02</b> No central workplace</span><span><b>03</b> Signed peer handshake</span><span><b>04</b> Encrypted transport</span></div></div></section>
        <section className="platforms container"><div className="eyebrow">ONE CAPSI</div><h2>One product identity. Different devices.</h2><p className="section-lead">The application is being developed around a shared interface and shared core for Windows, Android, macOS and iOS.</p><div className="platform-grid"><Platform name="Windows" status="Current release focus" /><Platform name="Android" status="Active validation" /><Platform name="macOS" status="In development" /><Platform name="iOS" status="In development" /></div></section>
        <section className="download"><img className="download-logo" src={logoUrl} alt="Capsi" /><div className="eyebrow">CAPSI 1.0.2</div><h2>Ready to connect?</h2><p>Install Capsi on your computer. Find another device. Send.</p><a className="button" href={downloadUrl}>Download for Windows</a><small>Windows 64-bit installer · Current release focus</small></section>
      </main>
      <footer><div className="footer-main"><div className="footer-brand"><img src={logoUrl} alt="" /><strong>CAPSI</strong></div><span>Messages and files, device to device.</span></div><div className="footer-connect"><div className="footer-label">CONNECT</div><div className="footer-links"><a href="https://x.com/runcapsi" target="_blank" rel="noreferrer" aria-label="Capsi on X"><span className="footer-icon">{icons.x}</span><span>@runcapsi</span></a><a href="mailto:developer@capsi.win" aria-label="Email Capsi developers"><span className="footer-icon">{icons.mail}</span><span>developer@capsi.win</span></a></div></div><span className="copyright">© {new Date().getFullYear()} CAPSICOM</span></footer>
    </div>
  );
}
function Step({ n, title, text }) { return <article className="step"><span className="step-number">{n}</span><h3>{title}</h3><p>{text}</p></article>; }
function Feature({ icon, title, text }) { return <article className="feature"><div className="feature-icon">{icon}</div><h3>{title}</h3><p>{text}</p></article>; }
function Platform({ name, status }) {
  const logos = {
    Windows: (
      <svg viewBox="0 0 24 24" aria-hidden="true" className="platform-svg">
        <path fill="currentColor" d="M2 4.5 10.5 3.3v8.2H2V4.5Zm9.8-1.35L22 1.7v9.8h-10.2V3.15ZM2 12.5h8.5v8.2L2 19.5v-7Zm9.8 0H22v9.8l-10.2-1.45V12.5Z"/>
      </svg>
    ),
    Android: (
      <svg viewBox="0 0 24 24" aria-hidden="true" className="platform-svg">
        <path fill="currentColor" d="M7.1 7.4 5.55 4.72a.65.65 0 1 1 1.12-.65l1.53 2.64A8.2 8.2 0 0 1 12 5.8c1.35 0 2.63.32 3.76.9l1.57-2.63a.65.65 0 1 1 1.12.67L16.9 7.42A7.65 7.65 0 0 1 19.7 13v4.25c0 .96-.78 1.75-1.75 1.75h-.95v2.45a1.05 1.05 0 1 1-2.1 0V19h-5.8v2.45a1.05 1.05 0 1 1-2.1 0V19h-.95A1.75 1.75 0 0 1 4.3 17.25V13a7.65 7.65 0 0 1 2.8-5.6ZM8.1 11.1a.9.9 0 1 0 0-1.8.9.9 0 0 0 0 1.8Zm7.8 0a.9.9 0 1 0 0-1.8.9.9 0 0 0 0 1.8Z"/>
      </svg>
    ),
    macOS: (
      <svg viewBox="0 0 24 24" aria-hidden="true" className="platform-svg">
        <path fill="currentColor" d="M16.8 12.7c0-2 1.7-3 1.8-3.1-1-.9-2.4-1-2.9-1-1.2-.1-2.4.7-3 .7-.7 0-1.6-.7-2.6-.7-1.4 0-2.7.8-3.4 2.1-1.5 2.5-.4 6.2 1.1 8.3.7 1 1.6 2 2.7 2 1.1 0 1.5-.7 2.9-.7 1.3 0 1.7.7 2.8.7 1.2 0 2-1 2.7-2 .9-1.2 1.2-2.4 1.2-2.5-.1 0-3.3-1.3-3.3-3.8Zm-2-5.4c.6-.8 1-1.8.9-2.8-.9 0-2 .6-2.6 1.3-.6.7-1.1 1.7-1 2.7 1 .1 2-.4 2.7-1.2Z"/>
      </svg>
    ),
    iOS: (
      <svg viewBox="0 0 24 24" aria-hidden="true" className="platform-svg">
        <path fill="currentColor" d="M16.8 12.7c0-2 1.7-3 1.8-3.1-1-.9-2.4-1-2.9-1-1.2-.1-2.4.7-3 .7-.7 0-1.6-.7-2.6-.7-1.4 0-2.7.8-3.4 2.1-1.5 2.5-.4 6.2 1.1 8.3.7 1 1.6 2 2.7 2 1.1 0 1.5-.7 2.9-.7 1.3 0 1.7.7 2.8.7 1.2 0 2-1 2.7-2 .9-1.2 1.2-2.4 1.2-2.5-.1 0-3.3-1.3-3.3-3.8Zm-2-5.4c.6-.8 1-1.8.9-2.8-.9 0-2 .6-2.6 1.3-.6.7-1.1 1.7-1 2.7 1 .1 2-.4 2.7-1.2Z"/>
      </svg>
    )
  };
  return <div className="platform"><span className="platform-icon">{logos[name] ?? <span className="platform-fallback">•</span>}</span><div><strong>{name}</strong><small>{status}</small></div></div>;
}
function AppPreview() { return <div className="app-preview"><div className="window-bar"><span className="window-logo"><img src={logoUrl} alt="" /></span><b>Capsi</b><span className="window-more">•••</span></div><div className="preview-body"><aside><div className="preview-nav active">Conversations</div><div className="preview-nav">Nearby</div><div className="preview-nav">Files</div><div className="preview-nav">WorkPlace</div></aside><div className="preview-main"><div className="preview-title">Nearby</div><div className="device-row"><span className="avatar">OP</span><div><b>Office PC</b><small>Trusted device</small></div><span className="online">●</span></div><div className="device-row"><span className="avatar">LP</span><div><b>Laptop</b><small>Available to connect</small></div><span className="online">●</span></div><div className="preview-empty"><img src={logoUrl} alt="" /><b>Find devices. Send.</b><span>Messages and files, device to device.</span></div></div></div></div>; }
createRoot(document.getElementById('root')).render(<App />);
