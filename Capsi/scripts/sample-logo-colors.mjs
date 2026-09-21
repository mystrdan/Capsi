// Minimal pure-Node PNG RGBA decoder (no native deps).
// Samples dominant colors (by frequency) from the supplied logo.
// Usage:  node scripts/sample-logo-colors.mjs [path/to/logo.png]
import { readFileSync } from 'node:fs';
import { inflateSync } from 'node:zlib';

const file = process.argv[2] || 'd:/Capsi/Source/capsi-logo.png';
const buf = readFileSync(file);
let p = 0;
const read = (n) => { const b = buf.subarray(p, p + n); p += n; return b; };
const u32 = (b) => b.readUInt32BE(0);
const u16 = (b) => b.readUInt16BE(0);

const sig = buf.subarray(0, 8);
if (sig[0] !== 137 || sig[1] !== 80 || sig[2] !== 78 || sig[3] !== 71 ||
        sig[4] !== 13 || sig[5] !== 10 || sig[6] !== 26 || sig[7] !== 10) {
  console.error('Not a PNG:', file, 'header:', [...sig].map(x => x.toString(16).padStart(2, '0')).join(' '));
  process.exit(1);
}
p = 8;
let width = 0, height = 0, bitDepth = 8, colorType = 0;
let palette = null, trnsAlpha = null;
let idat = [];
while (p < buf.length) {
  const len = u32(read(4));
  const type = read(4).toString('ascii');
  const data = read(len);
  read(4); // crc
  if (type === 'IHDR') {
    width = u32(data.subarray(0,4)); height = u32(data.subarray(4,8));
    bitDepth = data[8]; colorType = data[9];
    continue;
  }
  if (type === 'PLTE') { palette = data; continue; }
  if (type === 'tRNS') { trnsAlpha = data; continue; }
  if (type === 'IDAT') { idat.push(data); continue; }
  if (type === 'IEND') break;
}
const channels = (colorType & 3) + 1 + (colorType & 4 ? 1 : 0);
const bpp = channels * (bitDepth >= 8 ? Math.ceil(bitDepth / 8) : 1);

const raw = inflateSync(Buffer.concat(idat));
const bytesPerPixel = channels; // assume 8-bit
const pix = Buffer.alloc(width * height * 4);

function paeth(a, b, c) {
  const pr = a + b - c;
  const pa = Math.abs(pr - a), pb = Math.abs(pr - b), pc = Math.abs(pr - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}
let prev = Buffer.alloc(width * bytesPerPixel).fill(0);
let off = 0;
for (let y = 0; y < height; y++) {
  const filt = raw[y * (1 + width * bytesPerPixel)];
  let line = Buffer.from(raw.subarray(1 + y * (1 + width * bytesPerPixel), 1 + (y + 1) * (1 + width * bytesPerPixel)));
  line = Recon(line, prev, filt, bytesPerPixel);
  prev = line;
  for (let i = 0; i < width * bytesPerPixel; i += bytesPerPixel) {
    let r, g, b, a = 255;
    if (colorType === 6 || colorType === 4) { r = line[i]; g = line[i+1]; b = line[i+2]; if (colorType==6) a = line[i+3]; }
    else if (colorType === 2) { r=line[i]; g=line[i+1]; b=line[i+2]; }
    else if (colorType === 0) { r=g=b=line[i]; }
    else if (colorType === 3) { const idx=line[i]; r=palette[idx*3]; g=palette[idx*3+1]; b=palette[idx*3+2]; if(trnsAlpha && idx < trnsAlpha.length) a=trnsAlpha[idx]; }
    else { r=g=b=line[i]; }
    pix[off++] = r; pix[off++] = g; pix[off++] = b; pix[off++] = a;
  }
}

function Recon(cur, prevRow, filt, bpp) {
  const out = Buffer.from(cur);
  const px = (i) => out[i];
  const pxp = (i) => prevRow[i];
  const pxb = (i) => out[i - bpp];
  for (let i = 0; i < out.length; i++) {
    const x = bpp;
    if (filt === 0) continue;
    if (filt === 1) out[i] = (out[i] + (i >= bpp ? out[i-bpp] : 0)) & 255;
    else if (filt === 2) out[i] = (out[i] + pxp(i)) & 255;
    else if (filt === 3) out[i] = (out[i] + ((pxb(i) + pxp(i)) >> 1)) & 255;
    else if (filt === 4) out[i] = (out[i] + paeth(pxb(i), pxp(i), prevRow[i-bpp >=0 ? i-bpp : 0])) & 255;
  }
  return out;
}

// Count (quantized) colors, skip fully transparent.
const map = new Map();
const step = 8;
for (let i = 0; i < pix.length; i += 4) {
  if (pix[i+3] === 0) continue;
  const r = (pix[i] & 0xF8) | (pix[i] >> 5); // quantize to 32 buckets-ish; keep readable hex later
  const key = `${(pix[i]).toString(16).padStart(2,'0')}${(pix[i+1]).toString(16).padStart(2,'0')}${(pix[i+2]).toString(16).padStart(2,'0')}`;
  map.set(key, (map.get(key) || 0) + 1);
}
const counts = [...map.entries()].sort((a,b)=>b[1]-a[1]);
console.log(`Logo ${width}x${height} (colorType ${colorType}, bitDepth ${bitDepth})`);
console.log('Top colors (#RRGGBB : count):');
for (const [k,v] of counts.slice(0,12)) console.log(`  #${k} : ${v}`);
