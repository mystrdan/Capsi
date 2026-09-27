import React from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';

const downloadUrl = 'https://github.com/mystrdan/Capsi/releases/latest/download/Capsi_1.0.2_x64-setup.exe';
const logoUrl = 'https://raw.githubusercontent.com/mystrdan/Capsi/main/Capsi/icons/capsi-logo-512.png';

const Icon = ({ children }) => <span className="feature-icon" aria-hidden="true">{children}</span>;

function App() {
  const scrollTo = (id) => document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });

  return (
    <div className="site">
      <header className="nav">
        <a className="brand" href="/" aria-label="Capsi home">
          <img src={logoUrl} alt="" /><span>CAPSI</span>
        </a>
        <nav>
          <button onClick={() => scrollTo('how')}>How it works</button>
          <button onClick={() => scrollTo('features')}>Features</button>
          <button onClick={() => scrollTo('workplace')}>WorkPlace</button>
          <a className="button small" href={downloadUrl}>Download</a>
        </nav>
      </header>

      <main>
        <section className="hero">
          <div className="hero-copy">
            <div className="eyebrow">CAPSI</div>
            <h1>Run it.<br />Find devices.<br />Send.</h1>
            <h2>Messages and files, device to device.</h2>
            <p>Capsi is a lightweight communication utility for connected devices. Discover nearby Capsi devices, accept trusted peers, exchange messages and transfer files directly.</p>
            <div className="facts">
              <span>Device to device</span><span>No account</span><span>No Capsi cloud</span><span>Local-first</span>
            </div>
            <div className="actions">
              <a className="button" href={downloadUrl}>Download Capsi</a>
              <button className="button outline" onClick={() => scrollTo('how')}>See how it works</button>
            </div>
            <small>Windows 64-bit · Current release focus · Free to download and use</small>
          </div>
          <AppPreview />
        </section>

        <section className="statement">
          <div className="statement-mark"><img src={logoUrl} alt="" /></div>
          <div><div className="eyebrow">THE IDEA</div><h2>Communication does not always need a middleman.</h2></div>
          <p>When your devices can reach one another, Capsi lets them communicate directly. Wi-Fi, wired Ethernet, hotspot, or another supported local communication network — the product stays focused on the devices in front of you.</p>
        </section>

        <section id="how" className="dark-section">
          <div className="container">
            <div className="eyebrow">SIMPLE BY DESIGN</div>
            <h2>Run. Find. Send.</h2>
            <div className="steps">
              <Step n="01" title="Run" text="Install Capsi and give your device a name. Your device identity stays local." />
              <Step n="02" title="Find" text="Capsi discovers other Capsi devices on the connected network." />
              <Step n="03" title="Trust" text="Accept a device before treating it as a trusted peer." />
              <Step n="04" title="Send" text="Exchange direct messages and offer files to another trusted device." />
            </div>
          </div>
        </section>

        <section id="features" className="features container">
          <div className="eyebrow">THE USEFUL PARTS</div>
          <h2>Everything you need. Nothing that gets in the way.</h2>
          <div className="feature-grid">
            <Feature icon={<Icon>⌁</Icon>} title="Nearby" text="Discover other Capsi devices on your connected network without manually typing addresses." />
            <Feature icon={<Icon>⌁</Icon>} title="Messages" text="Keep direct one-to-one conversations between devices with local conversation history." />
            <Feature icon={<Icon>⇧</Icon>} title="Files" text="Offer files directly, with acceptance, integrity checks, delivery handling and resumable transfers." />
            <Feature icon={<Icon>✓</Icon>} title="Trusted devices" text="Accept, block, rename or forget peers. New devices do not become trusted automatically." />
            <Feature icon={<Icon>↻</Icon>} title="Offline delivery" text="Pending messages can remain local and retry when a recipient becomes reachable." />
            <Feature icon={<Icon>⌕</Icon>} title="Direct transport" text="Peer communication uses a signed handshake and encrypted transport rather than a Capsi cloud service." />
          </div>
        </section>

        <section id="workplace" className="workplace">
          <div className="container workplace-layout">
            <div className="workplace-copy">
              <div className="eyebrow">OPTIONAL · WORKPLACE</div>
              <h2>A workplace layer without a workplace server.</h2>
              <p>WorkPlace adds structure for trusted Capsi devices while keeping the local-first model. Create people, groups and departments, assign roles and permissions, send broadcasts and have workplace conversations.</p>
              <div className="workplace-list">
                <span>People & roles</span><span>Groups</span><span>Departments</span><span>Broadcasts</span><span>Workplace conversations</span><span>Direct synchronization</span>
              </div>
            </div>
            <div className="workplace-card">
              <div className="mini-header"><img src={logoUrl} alt="" /><strong>WorkPlace</strong><span>Local</span></div>
              <div className="mini-row"><b>People</b><span>12</span></div>
              <div className="mini-row"><b>Groups</b><span>4</span></div>
              <div className="mini-row"><b>Departments</b><span>3</span></div>
              <div className="mini-row"><b>Broadcasts</b><span>8</span></div>
              <div className="mini-note">Trusted devices · Direct synchronization</div>
            </div>
          </div>
        </section>

        <section className="split security">
          <div><div className="eyebrow">LOCAL FIRST</div><h2>Your devices. Your network. Your data.</h2></div>
          <div>
            <p>Capsi does not require a central Capsi cloud service, account system or central workplace server for local communication.</p>
            <div className="security-points"><span><b>01</b> No signup</span><span><b>02</b> No central workplace</span><span><b>03</b> Signed peer handshake</span><span><b>04</b> Encrypted transport</span></div>
          </div>
        </section>

        <section className="platforms container">
          <div className="eyebrow">ONE CAPSI</div>
          <h2>One product identity. Different devices.</h2>
          <p className="section-lead">The application is being developed around a shared interface and shared core for Windows, Android, macOS and iOS.</p>
          <div className="platform-grid">
            <Platform name="Windows" status="Current release focus" />
            <Platform name="Android" status="Active validation" />
            <Platform name="macOS" status="In development" />
            <Platform name="iOS" status="In development" />
          </div>
        </section>

        <section className="download">
          <img className="download-logo" src={logoUrl} alt="Capsi" />
          <div className="eyebrow">CAPSI 1.0.2</div>
          <h2>Ready to connect?</h2>
          <p>Install Capsi on your computer. Find another device. Send.</p>
          <a className="button" href={downloadUrl}>Download for Windows</a>
          <small>Windows 64-bit installer · Current release focus</small>
        </section>
      </main>

      <footer>
        <div className="footer-brand"><img src={logoUrl} alt="" /> <strong>CAPSI</strong></div>
        <span>Messages and files, device to device.</span>
        <span>© {new Date().getFullYear()} CAPSICOM</span>
      </footer>
    </div>
  );
}

function Step({ n, title, text }) {
  return <article className="step"><span className="step-number">{n}</span><h3>{title}</h3><p>{text}</p></article>;
}

function Feature({ icon, title, text }) {
  return <article className="feature"><div>{icon}</div><h3>{title}</h3><p>{text}</p></article>;
}

function Platform({ name, status }) {
  return <div className="platform"><span className="platform-icon">□</span><div><strong>{name}</strong><small>{status}</small></div></div>;
}

function AppPreview() {
  return <div className="app-preview">
    <div className="window-bar"><span className="window-logo"><img src={logoUrl} alt="" /></span><b>Capsi</b><span className="window-more">•••</span></div>
    <div className="preview-body">
      <aside>
        <div className="preview-nav active">Conversations</div>
        <div className="preview-nav">Nearby</div>
        <div className="preview-nav">Files</div>
        <div className="preview-nav">WorkPlace</div>
      </aside>
      <div className="preview-main">
        <div className="preview-title">Nearby</div>
        <div className="device-row"><span className="avatar">OP</span><div><b>Office PC</b><small>Trusted device</small></div><span className="online">●</span></div>
        <div className="device-row"><span className="avatar">LP</span><div><b>Laptop</b><small>Available to connect</small></div><span className="online">●</span></div>
        <div className="preview-empty"><img src={logoUrl} alt="" /><b>Find devices. Send.</b><span>Messages and files, device to device.</span></div>
      </div>
    </div>
  </div>;
}

createRoot(document.getElementById('root')).render(<App />);
