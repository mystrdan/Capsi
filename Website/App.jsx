import React from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';

const downloadUrl = 'https://github.com/mystrdan/Capsi/releases/latest/download/Capsi_1.0.2_x64-setup.exe';

function App() {
  const scrollTo = (id) => document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });

  return (
    <div className="site">
      <header className="nav">
        <a className="brand" href="/" aria-label="Capsi home"><span className="brand-mark">C</span><span>CAPSI</span></a>
        <nav>
          <button onClick={() => scrollTo('how')}>How it works</button>
          <button onClick={() => scrollTo('features')}>Features</button>
          <a className="button small" href={downloadUrl}>Download</a>
        </nav>
      </header>

      <main>
        <section className="hero">
          <div className="hero-copy">
            <div className="eyebrow">CAPSI</div>
            <h1>Run it.<br />Find devices.<br />Send.</h1>
            <h2>Messages and files, device to device.</h2>
            <p>Capsi lets connected devices discover each other and communicate directly. No cloud service. No accounts. No unnecessary infrastructure.</p>
            <div className="facts"><span>Device to device</span><span>No account</span><span>No internet required</span></div>
            <div className="actions"><a className="button" href={downloadUrl}>Download Capsi</a><button className="button outline" onClick={() => scrollTo('how')}>See how it works</button></div>
            <small>Windows (64-bit) · Free to download and use</small>
          </div>
          <Preview />
        </section>

        <section className="split">
          <div><div className="eyebrow">THE IDEA</div><h2>Communication does not always need a middleman.</h2></div>
          <p>Capsi is built around a simple idea: when your devices can reach each other, they should be able to talk to each other. Your setup can be Wi-Fi, wired Ethernet, a hotspot, or another connected local network.</p>
        </section>

        <section id="how" className="dark-section">
          <div className="container">
            <div className="eyebrow">SIMPLE BY DESIGN</div><h2>How it works</h2>
            <div className="cards">
              <Step n="01" title="Run" text="Install Capsi and give your device a name." />
              <Step n="02" title="Find" text="Capsi discovers other Capsi devices nearby." />
              <Step n="03" title="Send" text="Accept a device, then send messages and files." />
            </div>
          </div>
        </section>

        <section id="features" className="features container">
          <div className="eyebrow">WHAT YOU GET</div><h2>The useful parts. Nothing extra.</h2>
          <div className="cards">
            {[
              ['◌','Device Discovery','See nearby Capsi devices without typing addresses.'],
              ['◯','Direct Messages','Send one-to-one messages between accepted devices.'],
              ['□','File Transfer','Offer files directly to another trusted device.'],
              ['✓','Device Trust','New devices wait for you to accept them.'],
              ['×','No Cloud','Local conversations and transfers do not need a Capsi cloud.'],
              ['○','No Account','No signup or login. Your device identity is local.'],
            ].map(([icon,title,text]) => <article className="card" key={title}><b className="icon">{icon}</b><h3>{title}</h3><p>{text}</p></article>)}
          </div>
        </section>

        <section className="split local">
          <div><div className="eyebrow">LOCAL FIRST</div><h2>Your devices. Your network. Your data.</h2></div>
          <p>Capsi does not need an external chat service to move messages and files between connected devices. No cloud account, no login, and no internet connection is required for local communication.</p>
        </section>

        <section className="download">
          <div className="eyebrow">CAPSI</div><h2>Ready to connect?</h2>
          <p>Run Capsi on your computers. Find each other. Send messages and files.</p>
          <a className="button" href={downloadUrl}>Download Capsi</a>
        </section>
      </main>
      <footer>CAPSI · Messages and files, device to device.</footer>
    </div>
  );
}

function Step({ n, title, text }) {
  return <article className="card step"><span>{n}</span><h3>{title}</h3><p>{text}</p></article>;
}

function Preview() {
  return <div className="preview"><div className="window-bar"><span className="dot" /> <b>Capsi</b><span>•••</span></div><div className="preview-body"><aside><b>Nearby</b><div>Office PC</div><div>Laptop</div></aside><div className="preview-main"><div className="device-icon">⌁</div><b>Find devices. Send.</b></div></div></div>;
}

createRoot(document.getElementById('root')).render(<App />);
