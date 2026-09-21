// Samples the green stem accent + neutral ramp from the official Capsi logo.
// Usage: node scripts/sample-green.mjs <logo.png>
import { readFileSync } from 'node:fs';
import { inflateSync } from 'node:zlib';

const path = process.argv[2];
if (!path) {
  console.error('usage: node scripts/sample-green.mjs <logo.png>');
  process.exit(1);
}

const buf = readFileSync(path);
let off = 8;
let width = 0;
let height = 0;
let colorType = 0;
let bitDepth = 0;
const idat = [];
while (off < buf.length) {
  const len = buf.readUInt32BE(off);
  const type = buf.toString('ascii', off + 4, off + 8);
  const data = buf.subarray(off + 8, off + 8 + len);
  if (type === 'IHDR') {
    width = data.readUInt32BE(0);
    height = data.readUInt32BE(4);
    bitDepth = data[8];
    colorType = data[9];
  } else if (type === 'IDAT') {
    idat.push(data);
  } else if (type === 'IEND') {
    break;
  }
  off += 12 + len;
}
if (bitDepth !== 8 || (colorType !== 6 && colorType !== 2)) {
  console.error('only 8-bit RGB/RGBA supported, got', colorType, bitDepth);
  process.exit(1);
}

const bpp = colorType === 6 ? 4 : 3;
const raw = inflateSync(Buffer.concat(idat));
const stride = width * bpp;
const px = Buffer.alloc(height * stride);
for (let y = 0; y < height; y++) {
  const filter = raw[y * (stride + 1)];
  const src = y * (stride + 1) + 1;
  const dst = y * stride;
  for (let x = 0; x < stride; x++) {
    const cur = raw[src + x];
    const a = x >= bpp ? px[dst + x - bpp] : 0;
    const b = y > 0 ? px[dst - stride + x] : 0;
    const c = x >= bpp && y > 0 ? px[dst - stride + x - bpp] : 0;
    let v;
    switch (filter) {
      case 0: v = cur; break;
      case 1: v = cur + a; break;
      case 2: v = cur + b; break;
      case 3: v = cur + ((a + b) >> 1); break;
      case 4: {
        const p = a + b - c;
        const pa = Math.abs(p - a);
        const pb = Math.abs(p - b);
        const pc = Math.abs(p - c);
        v = cur + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c);
        break;
      }
      default: v = cur;
    }
    px[dst + x] = v & 0xff;
  }
}

// Classify every pixel; the stem is the only saturated green in the artwork.
const greens = [];
const ramps = new Map();
for (let y = 0; y < height; y++) {
  for (let x = 0; x < width; x++) {
    const i = y * stride + x * bpp;
    const r = px[i];
    const g = px[i + 1];
    const b = px[i + 2];
    const alpha = bpp === 4 ? px[i + 3] : 255;
    if (alpha < 200) continue;
    const mx = Math.max(r, g, b);
    const mn = Math.min(r, g, b);
    const sat = mx === 0 ? 0 : (mx - mn) / mx;
    if (sat > 0.25 && g === mx) {
      greens.push([r, g, b]);
    } else if (sat < 0.12) {
      const key = `${r},${g},${b}`;
      ramps.set(key, (ramps.get(key) ?? 0) + 1);
    }
  }
}

function hex([r, g, b]) {
  return '#' + [r, g, b].map((v) => v.toString(16).padStart(2, '0')).join('');
}

if (greens.length) {
  const avg = greens
    .reduce((acc, c) => [acc[0] + c[0], acc[1] + c[1], acc[2] + c[2]], [0, 0, 0])
    .map((v) => Math.round(v / greens.length));
  const sorted = greens.slice().sort((p, q) => q[1] - p[1]);
  console.log(`logo ${width}x${height}  green px: ${greens.length}`);
  console.log('  stem average :', hex(avg), avg);
  console.log('  brightest    :', hex(sorted[0]), sorted[0]);
  console.log('  darkest      :', hex(sorted[sorted.length - 1]), sorted[sorted.length - 1]);
  const mid = sorted[Math.floor(sorted.length / 2)];
  console.log('  median       :', hex(mid), mid);
} else {
  console.log('no green pixels found');
}

console.log('\nneutral ramp (top 12):');
[...ramps.entries()]
  .sort((a, b) => b[1] - a[1])
  .slice(0, 12)
  .forEach(([k, n]) => {
    const [r, g, b] = k.split(',').map(Number);
    console.log('  ', hex([r, g, b]), String(n).padStart(8));
  });