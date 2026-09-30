// Generates the Capsi application icon assets from the official logo.
//
// The supplied logo is authoritative, so this script never redraws it: it only
// removes empty margins, scales it with a box filter and re-encodes it as the
// PNG sizes + multi-resolution Windows `.ico` used by the Flutter Windows
// runner, and as the Android launcher set (legacy + adaptive foreground icons,
// the adaptive backdrop and the launch screen artwork).
//
// The logo artwork is light on transparency, so every launcher plate uses the
// Capsi ink backdrop (#090B0C, the same colour the Flutter theme paints its
// scaffold with) instead of letting launchers put it on white.
//
// Pure Node (zlib only) so it runs anywhere without native dependencies.
//
// Usage: node scripts/make-icons.mjs [source.png]
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { deflateSync, inflateSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const FLUTTER = join(HERE, '..', 'flutter');
const SRC = process.argv[2] || join(HERE, '..', 'icons', 'capsi-logo-512.png');

/* ------------------------------------------------------------------ decode */

export function decodePng(buf) {
  const sigOK = buf.length > 8 && buf.readUInt32BE(0) === 0x89504e47;
  if (!sigOK) throw new Error('not a PNG');

  let p = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 8;
  let colorType = 0;
  let palette = null;
  let trns = null;
  const idat = [];

  while (p + 8 <= buf.length) {
    const len = buf.readUInt32BE(p);
    const type = buf.toString('ascii', p + 4, p + 8);
    const data = buf.subarray(p + 8, p + 8 + len);
    p += 12 + len;
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
    } else if (type === 'PLTE') palette = data;
    else if (type === 'tRNS') trns = data;
    else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
  }
  if (bitDepth !== 8) throw new Error(`unsupported bit depth ${bitDepth}`);
  if (![0, 2, 3, 4, 6].includes(colorType)) throw new Error(`unsupported color type ${colorType}`);

  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[colorType];
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const out = Buffer.alloc(width * height * 4);

  let prevRow = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const src = y * (stride + 1) + 1;
    // Reconstruct the row into a scanline buffer using the standard PNG
    // filters (operating on raw sample bytes, widened to RGBA below).
    const line = Buffer.from(raw.subarray(src, src + stride));
    const up = prevRow;
    for (let i = 0; i < stride; i++) {
      const left = i >= channels ? line[i - channels] : 0;
      const above = up[i];
      const upperLeft = i >= channels ? up[i - channels] : 0;
      let v = line[i];
      if (filter === 1) v += left;
      else if (filter === 2) v += above;
      else if (filter === 3) v += (left + above) >> 1;
      else if (filter === 4) {
        const pp = left + above - upperLeft;
        const pa = Math.abs(pp - left);
        const pb = Math.abs(pp - above);
        const pc = Math.abs(pp - upperLeft);
        v += pa <= pb && pa <= pc ? left : pb <= pc ? above : upperLeft;
      }
      line[i] = v & 0xff;
    }
    prevRow = line;

    for (let x = 0; x < width; x++) {
      const i = x * channels;
      const o = (y * width + x) * 4;
      if (colorType === 6) {
        out[o] = line[i]; out[o + 1] = line[i + 1]; out[o + 2] = line[i + 2]; out[o + 3] = line[i + 3];
      } else if (colorType === 2) {
        out[o] = line[i]; out[o + 1] = line[i + 1]; out[o + 2] = line[i + 2]; out[o + 3] = 255;
      } else if (colorType === 0) {
        out[o] = out[o + 1] = out[o + 2] = line[i]; out[o + 3] = 255;
      } else if (colorType === 4) {
        out[o] = out[o + 1] = out[o + 2] = line[i]; out[o + 3] = line[i + 1];
      } else {
        const idx = line[i];
        out[o] = palette[idx * 3]; out[o + 1] = palette[idx * 3 + 1]; out[o + 2] = palette[idx * 3 + 2];
        out[o + 3] = trns && idx < trns.length ? trns[idx] : 255;
      }
    }
  }
  return { width, height, data: out };
}

/* ------------------------------------------------------------------ encode */

const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, crc]);
}

/** Encode straight RGBA (no per-row filter) as a PNG. */
export function encodePng(width, height, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // truecolour + alpha
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0;
    rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

/** DIB entry (BITMAPINFOHEADER + bottom-up BGRA + AND mask) for small ICO sizes. */
function encodeDib(size, rgba) {
  const header = Buffer.alloc(40);
  header.writeUInt32LE(40, 0);
  header.writeInt32LE(size, 4);
  header.writeInt32LE(size * 2, 8); // XOR bitmap + AND mask
  header.writeUInt16LE(1, 12);
  header.writeUInt16LE(32, 14);
  const xor = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const s = ((size - 1 - y) * size + x) * 4; // bottom-up
      const d = (y * size + x) * 4;
      xor[d] = rgba[s + 2];     // B
      xor[d + 1] = rgba[s + 1]; // G
      xor[d + 2] = rgba[s];     // R
      xor[d + 3] = rgba[s + 3]; // A
    }
  }
  const maskStride = ((size + 31) >> 5) * 4;
  return Buffer.concat([header, xor, Buffer.alloc(maskStride * size)]);
}

/** Multi-resolution `.ico`; small sizes as DIB, large sizes as PNG (Vista+). */
export function encodeIco(entries) {
  const dir = Buffer.alloc(6 + entries.length * 16);
  dir.writeUInt16LE(0, 0);
  dir.writeUInt16LE(1, 2);
  dir.writeUInt16LE(entries.length, 4);
  const blobs = [];
  let offset = dir.length;
  entries.forEach(({ size, rgba }, i) => {
    const blob = size >= 64 ? encodePng(size, size, rgba) : encodeDib(size, rgba);
    const e = 6 + i * 16;
    dir[e] = size >= 256 ? 0 : size;
    dir[e + 1] = size >= 256 ? 0 : size;
    dir[e + 2] = 0; // palette count
    dir[e + 3] = 0; // reserved
    dir.writeUInt16LE(1, e + 4);
    dir.writeUInt16LE(32, e + 6);
    dir.writeUInt32LE(blob.length, e + 8);
    dir.writeUInt32LE(offset, e + 12);
    offset += blob.length;
    blobs.push(blob);
  });
  return Buffer.concat([dir, ...blobs]);
}

/* ------------------------------------------------------------- image maths */

/** Tight bounding box of everything that is not effectively transparent. */
function contentBounds({ width, height, data }, threshold = 8) {
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (data[(y * width + x) * 4 + 3] > threshold) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return { x: 0, y: 0, w: width, h: height };
  return { x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1 };
}

function crop(src, box) {
  const out = Buffer.alloc(box.w * box.h * 4);
  for (let y = 0; y < box.h; y++) {
    src.data.copy(
      out,
      y * box.w * 4,
      ((box.y + y) * src.width + box.x) * 4,
      ((box.y + y) * src.width + box.x + box.w) * 4,
    );
  }
  return { width: box.w, height: box.h, data: out };
}

/**
 * Area-average resize to `size`x`size`, preserving the source aspect ratio and
 * centring it. `pad` (0..1) leaves a proportional margin; the logo's own
 * proportions are never altered.
 */
function resizeSquare(src, size, pad = 0) {
  const inner = Math.max(1, Math.round(size * (1 - pad * 2)));
  const scale = Math.min(inner / src.width, inner / src.height);
  const w = Math.max(1, Math.round(src.width * scale));
  const h = Math.max(1, Math.round(src.height * scale));
  const dx = Math.floor((size - w) / 2);
  const dy = Math.floor((size - h) / 2);
  const out = Buffer.alloc(size * size * 4);
  for (let y = 0; y < h; y++) {
    const sy0 = Math.floor((y * src.height) / h);
    const sy1 = Math.max(sy0 + 1, Math.round(((y + 1) * src.height) / h));
    for (let x = 0; x < w; x++) {
      const sx0 = Math.floor((x * src.width) / w);
      const sx1 = Math.max(sx0 + 1, Math.round(((x + 1) * src.width) / w));
      let r = 0; let g = 0; let b = 0; let a = 0; let n = 0;
      for (let sy = sy0; sy < sy1 && sy < src.height; sy++) {
        for (let sx = sx0; sx < sx1 && sx < src.width; sx++) {
          const i = (sy * src.width + sx) * 4;
          const alpha = src.data[i + 3] / 255;
          r += src.data[i] * alpha;
          g += src.data[i + 1] * alpha;
          b += src.data[i + 2] * alpha;
          a += src.data[i + 3];
          n++;
        }
      }
      if (!n) continue;
      const o = ((dy + y) * size + dx + x) * 4;
      const wa = a / n / 255;
      // Un-premultiply so semi-transparent edges keep their colour.
      out[o] = wa > 0 ? Math.min(255, Math.round(r / n / wa)) : 0;
      out[o + 1] = wa > 0 ? Math.min(255, Math.round(g / n / wa)) : 0;
      out[o + 2] = wa > 0 ? Math.min(255, Math.round(b / n / wa)) : 0;
      out[o + 3] = Math.round(a / n);
    }
  }
  return out;
}

/* ------------------------------------------------------------------ Android */

/**
 * Capsi ink (#090B0C): the plate the light logo artwork sits on. The Flutter
 * theme paints the same colour, so launcher and app agree on the background.
 */
const INK = [9, 11, 12];

/** Flatten a transparent layer over the ink plate; legacy launchers ignore alpha. */
function overInk(rgba, size) {
  const out = Buffer.alloc(size * size * 4);
  for (let i = 0; i < size * size; i++) {
    const a = rgba[i * 4 + 3] / 255;
    out[i * 4] = Math.round(rgba[i * 4] * a + INK[0] * (1 - a));
    out[i * 4 + 1] = Math.round(rgba[i * 4 + 1] * a + INK[1] * (1 - a));
    out[i * 4 + 2] = Math.round(rgba[i * 4 + 2] * a + INK[2] * (1 - a));
    out[i * 4 + 3] = 255;
  }
  return out;
}

/** Keep only the inside of a centred disc, for the legacy `ic_launcher_round`. */
function discCrop(rgba, size) {
  const out = Buffer.from(rgba);
  const r = size / 2;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const d = Math.hypot(x + 0.5 - r, y + 0.5 - r);
      if (d > r) out[(y * size + x) * 4 + 3] = 0;
      else if (d > r - 1) out[(y * size + x) * 4 + 3] = Math.round(out[(y * size + x) * 4 + 3] * (r - d));
    }
  }
  return out;
}

/**
 * Android launcher assets. Adaptive icons (API 26+) get a transparent
 * foreground layer plus an ink background colour, and the mark stays inside the
 * 66/108dp safe zone so no launcher mask (circle, squircle or rounded square)
 * can cut it. The pre-26 densities keep their own flattened PNG plates.
 */
function writeAndroidIcons(resDir, trimmed) {
  // Adaptive launchers mask the icon down to the centred 66/108dp circle, so the
  // corners of the mark's bounding box must stay inside that circle. Deriving the
  // margin from the artwork keeps tall marks like the Capsi logo intact, with a
  // little breathing room (0.30 of the canvas instead of the exact 0.3056 limit).
  const aspect = trimmed.width / trimmed.height;
  const safeHeight = Math.min(1, (2 * 0.3) / Math.hypot(aspect, 1));
  const foregroundPad = (1 - safeHeight) / 2;

  // 48dp legacy icons and the 108dp adaptive foreground canvas per density.
  const densities = [
    ['mdpi', 48, 108],
    ['hdpi', 72, 162],
    ['xhdpi', 96, 216],
    ['xxhdpi', 144, 324],
    ['xxxhdpi', 192, 432],
  ];

  for (const [dpi, legacy, canvas] of densities) {
    const dir = join(resDir, `mipmap-${dpi}`);
    mkdirSync(dir, { recursive: true });

    const plate = overInk(resizeSquare(trimmed, legacy, legacy <= 48 ? 0.12 : 0.1), legacy);
    writeFileSync(join(dir, 'ic_launcher.png'), encodePng(legacy, legacy, plate));
    writeFileSync(
      join(dir, 'ic_launcher_round.png'),
      encodePng(legacy, legacy, discCrop(plate, legacy)),
    );
    writeFileSync(
      join(dir, 'ic_launcher_foreground.png'),
      encodePng(canvas, canvas, resizeSquare(trimmed, canvas, foregroundPad)),
    );
    console.log(`  wrote android mipmap-${dpi} (launcher ${legacy}dp, foreground ${canvas}dp)`);
  }

  const adaptiveDir = join(resDir, 'mipmap-anydpi-v26');
  mkdirSync(adaptiveDir, { recursive: true });
  const adaptiveIcon = `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
`;
  for (const name of ['ic_launcher.xml', 'ic_launcher_round.xml']) {
    writeFileSync(join(adaptiveDir, name), adaptiveIcon);
  }
  console.log('  wrote android mipmap-anydpi-v26 adaptive icons');

  const valuesDir = join(resDir, 'values');
  mkdirSync(valuesDir, { recursive: true });
  writeFileSync(
    join(valuesDir, 'colors.xml'),
    `<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Capsi ink: launcher backdrop behind the light logo artwork. -->
    <color name="ic_launcher_background">#FF090B0C</color>
    <color name="capsi_ink">#FF090B0C</color>
</resources>
`,
  );
  console.log('  wrote android values/colors.xml');

  // The splash screen is drawn by the OS before Flutter starts, so it needs the
  // same ink plate; the stock template splash is white and flashes against the
  // app's dark theme.
  const splashDir = join(resDir, 'drawable-nodpi');
  mkdirSync(splashDir, { recursive: true });
  writeFileSync(
    join(splashDir, 'capsi_splash_logo.png'),
    encodePng(320, 320, resizeSquare(trimmed, 320, 0.06)),
  );
  const launchBackground = `<?xml version="1.0" encoding="utf-8"?>
<!-- Capsi launch screen: the mark on the ink plate the app opens on. -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/capsi_ink" />
    <item>
        <bitmap
            android:gravity="center"
            android:src="@drawable/capsi_splash_logo" />
    </item>
</layer-list>
`;
  for (const dir of ['drawable', 'drawable-v21']) {
    const target = join(resDir, dir);
    if (!existsSync(target)) continue;
    writeFileSync(join(target, 'launch_background.xml'), launchBackground);
  }
  console.log('  wrote android launch background');

  const manifestPath = join(resDir, '..', 'AndroidManifest.xml');
  if (existsSync(manifestPath)) {
    const manifest = readFileSync(manifestPath, 'utf8');
    if (!manifest.includes('android:roundIcon')) {
      writeFileSync(
        manifestPath,
        manifest.replace('android:icon="@mipmap/ic_launcher"', 'android:icon="@mipmap/ic_launcher"\n        android:roundIcon="@mipmap/ic_launcher_round"'),
      );
      console.log('  added android:roundIcon to the manifest');
    }
  }
}

/* -------------------------------------------------------------------- main */

function main() {
  const logo = decodePng(readFileSync(SRC));
  const box = contentBounds(logo);
  const trimmed = crop(logo, box);
  console.log(`source  : ${SRC}`);
  console.log(`canvas  : ${logo.width}x${logo.height}`);
  console.log(`trimmed : ${box.w}x${box.h} at (${box.x},${box.y})`);

  const winLogos = [
    ['Square30x30Logo.png', 30],
    ['Square44x44Logo.png', 44],
    ['Square71x71Logo.png', 71],
    ['Square89x89Logo.png', 89],
    ['Square107x107Logo.png', 107],
    ['Square142x142Logo.png', 142],
    ['Square150x150Logo.png', 150],
    ['Square284x284Logo.png', 284],
    ['Square310x310Logo.png', 310],
    ['StoreLogo.png', 50],
  ];

  const groups = [
    {
      dir: join(FLUTTER, 'assets'),
      files: [['capsi-logo-512.png', 512]],
    },
    {
      dir: join(HERE, '..', 'icons'),
      files: [['capsi-logo-512.png', 512], ['capsi-logo-256.png', 256], ['capsi-logo-64.png', 64]],
    },
    {
      dir: join(FLUTTER, 'windows', 'runner', 'resources'),
      files: [
        ['app-icon-512.png', 512],
        ...winLogos,
      ],
    },
  ];

  for (const { dir, files } of groups) {
    mkdirSync(dir, { recursive: true });
    for (const [name, size] of files) {
      const target = join(dir, name);
      // The trimmed-and-repadded render is not the original artwork: writing it
      // back over the source would zoom the mark a little on every run.
      if (resolve(target) === resolve(SRC)) {
        console.log(`  kept  ${target.replace(/\\/g, '/')} (source artwork, untouched)`);
        continue;
      }
      const png = encodePng(size, size, resizeSquare(trimmed, size, size <= 64 ? 0.06 : 0.03));
      writeFileSync(target, png);
      console.log(`  wrote ${target.replace(/\\/g, '/')} (${size}px, ${png.length} B)`);
    }
  }

  const ico = encodeIco(
    [16, 24, 32, 48, 64, 128, 256].map((size) => ({
      size,
      // The desktop icon carries its own ink plate: taskbars and Explorer
      // backings are not guaranteed to be dark, and the mark is light art.
      rgba: overInk(resizeSquare(trimmed, size, size <= 64 ? 0.09 : 0.06), size),
    })),
  );
  const icoPath = join(HERE, '..', 'flutter', 'windows', 'runner', 'resources', 'app_icon.ico');
  writeFileSync(icoPath, ico);
  console.log(`  wrote ${icoPath.replace(/\\/g, '/')} (7 sizes, ${ico.length} B)`);

  // Android only once the Flutter runner exists; the script is also run in CI
  // right after the runner is generated.
  const androidRes = join(FLUTTER, 'android', 'app', 'src', 'main', 'res');
  if (existsSync(join(FLUTTER, 'android', 'app'))) {
    writeAndroidIcons(androidRes, trimmed);
  } else {
    console.log('  skipped android launcher icons (no android/app runner yet)');
  }
}

if (process.argv[1] && process.argv[1].endsWith('make-icons.mjs')) main();