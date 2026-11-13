// Procedural asset generator for Void Clash 3D:
// 1. assets/fonts/main.font (en, pt, ru, tr + symbols)
// 2. assets/textures/palette_256.png (256x256 palette + 24 skins + emissives)
// 3. assets/models/*.gltf (self-contained low-poly glTF 2.0 meshes)
// 4. assets/sfx/*.wav (lightweight procedural 22kHz mono SFX)
// 5. assets/ui/*.png + assets/atlases/ui.atlas

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const ROOT = path.resolve(__dirname, "..");

// Seeded PRNG so noise-based SFX are identical on every run (no spurious git diffs).
{
  let seed = 20261113;
  Math.random = () => {
    seed = (seed * 16807) % 2147483647;
    return seed / 2147483647;
  };
}

function ensureDir(rel) {
  const full = path.join(ROOT, rel);
  fs.mkdirSync(full, { recursive: true });
  return full;
}

// ============================================================================
// Minimal PNG Encoder (RGBA)
// ============================================================================
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    }
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, "ascii");
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([len, typeBuf, data, crcBuf]);
}

function writePng(relPath, width, height, rgba) {
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    const rowStart = y * (width * 4 + 1);
    raw[rowStart] = 0; // filter none
    rgba.copy(raw, rowStart + 1, y * width * 4, (y + 1) * width * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  const idat = zlib.deflateSync(raw, { level: 9 });
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const out = Buffer.concat([
    sig,
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", idat),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
  const full = path.join(ROOT, relPath);
  fs.mkdirSync(path.dirname(full), { recursive: true });
  fs.writeFileSync(full, out);
}

function hexToRgba(hex, a = 255) {
  const h = hex.replace("#", "");
  return [
    parseInt(h.slice(0, 2), 16),
    parseInt(h.slice(2, 4), 16),
    parseInt(h.slice(4, 6), 16),
    a,
  ];
}

// ============================================================================
// 1. Font (main.font)
// ============================================================================
function generateFont() {
  const ascii = [];
  for (let c = 32; c <= 126; c++) ascii.push(String.fromCharCode(c));
  const extra =
    "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ" +
    "абвгдеёжзийклмнопрстуфхцчшщъыьэюя" +
    "ÁÀÂÃÉÊÍÓÔÕÚÇáàâãéêíóôõúç" +
    "ÇĞİÖŞÜçğıöşü" +
    "°×%+-•→—";

  const seen = new Set(ascii);
  let chars = ascii.join("");
  for (const ch of extra) {
    if (!seen.has(ch)) {
      seen.add(ch);
      chars += ch;
    }
  }

  let escaped = "";
  for (const ch of chars) {
    const code = ch.charCodeAt(0);
    if (ch === "\\" || ch === '"') {
      escaped += "\\" + ch;
    } else if (code >= 32 && code <= 126) {
      escaped += ch;
    } else {
      const buf = Buffer.from(ch, "utf8");
      for (const b of buf) {
        escaped += "\\" + b.toString(8).padStart(3, "0");
      }
    }
  }

  const content = `font: "/assets/fonts/Nunito-Black.ttf"
material: "/builtins/fonts/font-df.material"
size: 40
outline_alpha: 1.0
outline_width: 3.0
shadow_blur: 0
output_format: TYPE_DISTANCE_FIELD
render_mode: MODE_MULTI_LAYER
characters: "${escaped}"
`;
  fs.writeFileSync(path.join(ROOT, "assets/fonts/main.font"), content, "utf8");
}

// ============================================================================
// 2. Palette 256x256 (16x16 cells of 16x16 px)
// ============================================================================
const SKINS = [
  ["#2D8CFF", "#DCEEFF", "#1A2538", "#00E5FF"], // 0: Cobalt Ace (Player default)
  ["#E53935", "#FFCDD2", "#261619", "#FF7043"], // 1: Crimson Raider (Enemy default)
  ["#00BFA5", "#D7FFF7", "#14292B", "#64FFDA"], // 2: Teal Vanguard (Ally)
  ["#F5A623", "#FFF3D6", "#2B2112", "#FFD54F"], // 3: Solar Gold
  ["#8E24AA", "#F3E5F5", "#1F1429", "#EA80FC"], // 4: Void Amethyst
  ["#43A047", "#DCEDC8", "#18291A", "#69F0AE"], // 5: Emerald Viper
  ["#ECEFF1", "#FFFFFF", "#263238", "#26C6DA"], // 6: Arctic Wing
  ["#37474F", "#78909C", "#11171A", "#FF5252"], // 7: Stealth Carbon
  ["#F45B7A", "#FFE4EA", "#2D1820", "#FF80AB"], // 8: Coral Nova
  ["#D81B60", "#FCE4EC", "#24111B", "#00E5FF"], // 9: Cyber Magenta
  ["#D4A373", "#FAEDCD", "#2B2218", "#FFB703"], // 10: Dune Nomad
  ["#1E3A8A", "#93C5FD", "#0F172A", "#38BDF8"], // 11: Deep Navy
  ["#7CB342", "#F0F4C3", "#1C2412", "#C6FF00"], // 12: Toxic Strike
  ["#5E35B1", "#D1C4E9", "#17112B", "#7C4DFF"], // 13: Royal Nebula
  ["#EC407A", "#F8BBD0", "#29121C", "#FF4081"], // 14: Plasma Rose
  ["#8D6E63", "#D7CCC8", "#221A17", "#FFAB40"], // 15: Bronze Titan
  ["#00ACC1", "#E0F7FA", "#10282E", "#18FFFF"], // 16: Glacier Cyan
  ["#BF360C", "#FFCCBC", "#26120B", "#FF6E40"], // 17: Magma Core
  ["#26A69A", "#E0F2F1", "#132927", "#A7FFEB"], // 18: Mint Chrome
  ["#FB8C00", "#FFE0B2", "#2B1B08", "#FFAB00"], // 19: Blaze Orange
  ["#3949AB", "#C5CAE9", "#121730", "#536DFE"], // 20: Indigo Storm
  ["#558B2F", "#DCEDC8", "#1B2413", "#B2FF59"], // 21: Tactical Olive
  ["#FDD835", "#FFFDE7", "#2B260C", "#FFFF00"], // 22: Hornet Yellow
  ["#BA68C8", "#F3E5F5", "#241529", "#E040FB"], // 23: Starlight Orchid
];

function generatePalette() {
  const W = 256, H = 256;
  const buf = Buffer.alloc(W * H * 4);
  // Fill default dark grey
  for (let i = 0; i < W * H; i++) {
    buf[i * 4] = 30; buf[i * 4 + 1] = 36; buf[i * 4 + 2] = 48; buf[i * 4 + 3] = 255;
  }

  function fillCell(col, row, hex) {
    const [r, g, b, a] = hexToRgba(hex, 255);
    const x0 = col * 16, y0 = row * 16;
    for (let y = y0; y < y0 + 16; y++) {
      for (let x = x0; x < x0 + 16; x++) {
        const idx = (y * W + x) * 4;
        buf[idx] = r; buf[idx + 1] = g; buf[idx + 2] = b; buf[idx + 3] = a;
      }
    }
  }

  // Rows 0..5: 24 skins (4 skins per row, 4 cells per skin)
  for (let s = 0; s < SKINS.length; s++) {
    const row = Math.floor(s / 4);
    const baseCol = (s % 4) * 4;
    for (let t = 0; t < 4; t++) {
      fillCell(baseCol + t, row, SKINS[s][t]);
    }
  }

  // Row 8: Attachments / Turrets / Mechanical
  const row8 = ["#B0BEC5", "#607D8B", "#37474F", "#FFC107", "#CFD8DC", "#263238", "#00E5FF", "#FF5252"];
  row8.forEach((c, i) => fillCell(i, 8, c));

  // Row 9: Asteroids & Station
  const row9 = ["#546E7A", "#455A64", "#37474F", "#263238", "#78909C", "#90A4AE", "#4E342E", "#00B0FF"];
  row9.forEach((c, i) => fillCell(i, 9, c));

  // Row 10: Dreadnought Boss
  const row10 = ["#263238", "#37474F", "#B71C1C", "#FF5252", "#CFD8DC", "#FFAB00", "#00E5FF", "#101820"];
  row10.forEach((c, i) => fillCell(i, 10, c));

  // Row 14 & 15: Emissives (Beacons, Lasers, Thrusters, Shields)
  const row14 = [
    "#00E5FF", // 0: Player/Ally plasma & thruster
    "#FF3D00", // 1: Enemy plasma & thruster
    "#69F0AE", // 2: Repair / Green
    "#FFD740", // 3: Neutral / Gold beacon
    "#FF6D00", // 4: Missile flame
    "#E040FB", // 5: EMP / Void
    "#FFFFFF", // 6: Core white
    "#2979FF", // 7: Shield blue
    "#FF1744", // 8: Red core
    "#00E676", // 9: Emerald trail
    "#F50057", // 10: Magenta trail
    "#FFEA00", // 11: Yellow trail
  ];
  row14.forEach((c, i) => {
    fillCell(i, 14, c);
    fillCell(i, 15, c);
  });

  writePng("assets/textures/palette_256.png", W, H, buf);
}

// ============================================================================
// 3. Low-Poly glTF 2.0 Mesh Builder
// ============================================================================
function cellUV(col, row) {
  return [(col + 0.5) / 16, (row + 0.5) / 16];
}

class MeshBuilder {
  constructor() {
    this.positions = [];
    this.normals = [];
    this.uvs = [];
    this.indices = [];
  }

  addTri(a, b, c, col, row) {
    const ux = c[0] - a[0], uy = c[1] - a[1], uz = c[2] - a[2];
    const vx = b[0] - a[0], vy = b[1] - a[1], vz = b[2] - a[2];
    // Right-handed outward normal: (b - a) x (c - a)
    let nx = vy * uz - vz * uy;
    let ny = vz * ux - vx * uz;
    let nz = vx * uy - vy * ux;
    const len = Math.hypot(nx, ny, nz) || 1;
    nx /= len; ny /= len; nz /= len;

    const [u, v] = cellUV(col, row);
    const base = this.positions.length / 3;
    for (const p of [a, b, c]) {
      this.positions.push(p[0], p[1], p[2]);
      this.normals.push(nx, ny, nz);
      this.uvs.push(u, v);
    }
    this.indices.push(base, base + 1, base + 2);
  }

  addQuad(a, b, c, d, col, row) {
    this.addTri(a, b, c, col, row);
    this.addTri(a, c, d, col, row);
  }

  addBox(cx, cy, cz, sx, sy, sz, col, row) {
    const hx = sx * 0.5, hy = sy * 0.5, hz = sz * 0.5;
    const p = [
      [cx - hx, cy - hy, cz + hz], // 0: front-bot-left
      [cx + hx, cy - hy, cz + hz], // 1: front-bot-right
      [cx + hx, cy + hy, cz + hz], // 2: front-top-right
      [cx - hx, cy + hy, cz + hz], // 3: front-top-left
      [cx - hx, cy - hy, cz - hz], // 4: back-bot-left
      [cx + hx, cy - hy, cz - hz], // 5: back-bot-right
      [cx + hx, cy + hy, cz - hz], // 6: back-top-right
      [cx - hx, cy + hy, cz - hz], // 7: back-top-left
    ];
    this.addQuad(p[0], p[1], p[2], p[3], col, row); // +Z
    this.addQuad(p[5], p[4], p[7], p[6], col, row); // -Z
    this.addQuad(p[1], p[5], p[6], p[2], col, row); // +X
    this.addQuad(p[4], p[0], p[3], p[7], col, row); // -X
    this.addQuad(p[3], p[2], p[6], p[7], col, row); // +Y
    this.addQuad(p[4], p[5], p[1], p[0], col, row); // -Y
  }

  // Tapered fuselage prism along Z (-Z is forward nose, +Z is rear engine)
  addWedge(cx, cy, cz, wFront, hFront, wBack, hBack, len, col, row) {
    const zF = cz - len * 0.5, zB = cz + len * 0.5;
    const f = [
      [cx - wFront, cy - hFront, zF],
      [cx + wFront, cy - hFront, zF],
      [cx + wFront, cy + hFront, zF],
      [cx - wFront, cy + hFront, zF],
    ];
    const b = [
      [cx - wBack, cy - hBack, zB],
      [cx + wBack, cy - hBack, zB],
      [cx + wBack, cy + hBack, zB],
      [cx - wBack, cy + hBack, zB],
    ];
    this.addQuad(f[3], f[2], f[1], f[0], col, row); // front (-Z)
    this.addQuad(b[0], b[1], b[2], b[3], col, row); // back (+Z)
    this.addQuad(f[1], b[1], b[2], f[2], col, row); // +X
    this.addQuad(b[0], f[0], f[3], b[3], col, row); // -X
    this.addQuad(f[3], f[2], b[2], b[3], col, row); // +Y
    this.addQuad(b[0], b[1], f[1], f[0], col, row); // -Y
  }

  addWing(xInner, xOuter, y, zFrontIn, zBackIn, zFrontOut, zBackOut, thick, col, row) {
    const t = thick * 0.5;
    // Top & bottom + edges
    const ti = [xInner, y + t, zFrontIn], to = [xOuter, y + t, zFrontOut];
    const bo = [xOuter, y + t, zBackOut], bi = [xInner, y + t, zBackIn];
    const ti2 = [xInner, y - t, zFrontIn], to2 = [xOuter, y - t, zFrontOut];
    const bo2 = [xOuter, y - t, zBackOut], bi2 = [xInner, y - t, zBackIn];
    if (xOuter > xInner) {
      this.addQuad(ti, bi, bo, to, col, row); // top
      this.addQuad(to2, bo2, bi2, ti2, col, row); // bottom
      this.addQuad(ti, to, to2, ti2, col, row); // leading
      this.addQuad(bo, bi, bi2, bo2, col, row); // trailing
      this.addQuad(to, bo, bo2, to2, col, row); // tip
    } else {
      this.addQuad(to, bo, bi, ti, col, row);
      this.addQuad(ti2, bi2, bo2, to2, col, row);
      this.addQuad(to, ti, ti2, to2, col, row);
      this.addQuad(bi, bo, bo2, bi2, col, row);
      this.addQuad(bo, to, to2, bo2, col, row);
    }
  }

  addSphere(cx, cy, cz, radius, segU, segV, col, row, noiseSeed = 0) {
    const pts = [];
    for (let iv = 0; iv <= segV; iv++) {
      const phi = (iv / segV) * Math.PI;
      const ring = [];
      for (let iu = 0; iu < segU; iu++) {
        const theta = (iu / segU) * Math.PI * 2;
        let r = radius;
        if (noiseSeed !== 0) {
          const n = Math.sin(theta * 3 + noiseSeed) * Math.cos(phi * 2 + noiseSeed * 1.7);
          r *= 1.0 + 0.22 * n;
        }
        ring.push([
          cx + r * Math.sin(phi) * Math.cos(theta),
          cy + r * Math.cos(phi),
          cz + r * Math.sin(phi) * Math.sin(theta),
        ]);
      }
      pts.push(ring);
    }
    for (let iv = 0; iv < segV; iv++) {
      for (let iu = 0; iu < segU; iu++) {
        const inx = (iu + 1) % segU;
        const a = pts[iv][iu], b = pts[iv][inx];
        const c = pts[iv + 1][inx], d = pts[iv + 1][iu];
        if (iv > 0) this.addTri(a, b, c, col, row);
        if (iv < segV - 1) this.addTri(a, c, d, col, row);
      }
    }
  }

  addTorus(cx, cy, cz, majorR, minorR, segMaj, segMin, col, row) {
    const rings = [];
    for (let i = 0; i < segMaj; i++) {
      const a = (i / segMaj) * Math.PI * 2;
      const cosA = Math.cos(a), sinA = Math.sin(a);
      const ring = [];
      for (let j = 0; j < segMin; j++) {
        const b = (j / segMin) * Math.PI * 2;
        const r = majorR + minorR * Math.cos(b);
        ring.push([
          cx + r * cosA,
          cy + minorR * Math.sin(b),
          cz + r * sinA,
        ]);
      }
      rings.push(ring);
    }
    for (let i = 0; i < segMaj; i++) {
      const ni = (i + 1) % segMaj;
      for (let j = 0; j < segMin; j++) {
        const nj = (j + 1) % segMin;
        this.addQuad(rings[i][j], rings[ni][j], rings[ni][nj], rings[i][nj], col, row);
      }
    }
  }

  exportGltf(relPath, name) {
    const posF32 = new Float32Array(this.positions);
    const normF32 = new Float32Array(this.normals);
    const uvF32 = new Float32Array(this.uvs);
    const idxU16 = new Uint16Array(this.indices);

    let min = [Infinity, Infinity, Infinity];
    let max = [-Infinity, -Infinity, -Infinity];
    for (let i = 0; i < posF32.length; i += 3) {
      for (let k = 0; k < 3; k++) {
        if (posF32[i + k] < min[k]) min[k] = posF32[i + k];
        if (posF32[i + k] > max[k]) max[k] = posF32[i + k];
      }
    }

    const posBuf = Buffer.from(posF32.buffer);
    const normBuf = Buffer.from(normF32.buffer);
    const uvBuf = Buffer.from(uvF32.buffer);
    const idxBuf = Buffer.from(idxU16.buffer);
    const pad = (idxBuf.length % 4 === 0) ? Buffer.alloc(0) : Buffer.alloc(4 - (idxBuf.length % 4));
    const bin = Buffer.concat([posBuf, normBuf, uvBuf, idxBuf, pad]);

    const gltf = {
      asset: { version: "2.0", generator: "VoidClash3D-Gen" },
      scene: 0,
      scenes: [{ nodes: [0] }],
      nodes: [{ name, mesh: 0 }],
      meshes: [{
        name,
        primitives: [{
          attributes: { POSITION: 0, NORMAL: 1, TEXCOORD_0: 2 },
          indices: 3,
          mode: 4,
        }],
      }],
      buffers: [{
        uri: "data:application/octet-stream;base64," + bin.toString("base64"),
        byteLength: bin.length,
      }],
      bufferViews: [
        { buffer: 0, byteOffset: 0, byteLength: posBuf.length, target: 34962 },
        { buffer: 0, byteOffset: posBuf.length, byteLength: normBuf.length, target: 34962 },
        { buffer: 0, byteOffset: posBuf.length + normBuf.length, byteLength: uvBuf.length, target: 34962 },
        { buffer: 0, byteOffset: posBuf.length + normBuf.length + uvBuf.length, byteLength: idxBuf.length, target: 34963 },
      ],
      accessors: [
        { bufferView: 0, componentType: 5126, count: posF32.length / 3, type: "VEC3", min, max },
        { bufferView: 1, componentType: 5126, count: normF32.length / 3, type: "VEC3" },
        { bufferView: 2, componentType: 5126, count: uvF32.length / 2, type: "VEC2" },
        { bufferView: 3, componentType: 5123, count: idxU16.length, type: "SCALAR" },
      ],
    };

    const full = path.join(ROOT, relPath);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, JSON.stringify(gltf), "utf8");
  }
}

function generateModels() {
  // 1. Interceptor (fast delta fighter, forward = -Z)
  {
    const m = new MeshBuilder();
    m.addWedge(0, 0, -0.4, 0.25, 0.14, 0.75, 0.42, 4.4, 0, 0); // hull primary
    m.addWedge(0, 0.36, -0.3, 0.22, 0.12, 0.42, 0.22, 1.8, 2, 0); // cockpit canopy
    m.addWing(0.65, 3.1, -0.05, 0.1, 1.5, 1.3, 2.0, 0.14, 0, 0); // R wing
    m.addWing(-0.65, -3.1, -0.05, 0.1, 1.5, 1.3, 2.0, 0.14, 0, 0); // L wing
    m.addWing(0.55, 1.4, 0.25, 0.8, 1.8, 1.2, 2.1, 0.10, 1, 0); // R tail fin
    m.addWing(-0.55, -1.4, 0.25, 0.8, 1.8, 1.2, 2.1, 0.10, 1, 0); // L tail fin
    m.addBox(1.4, -0.12, 0.5, 0.18, 0.18, 1.6, 3, 0); // R plasma barrel
    m.addBox(-1.4, -0.12, 0.5, 0.18, 0.18, 1.6, 3, 0); // L plasma barrel
    m.exportGltf("assets/models/ship_interceptor.gltf", "ship_interceptor");
  }

  // 2. Fighter (balanced swept-wing)
  {
    const m = new MeshBuilder();
    m.addWedge(0, 0, -0.2, 0.45, 0.24, 1.05, 0.58, 5.2, 0, 0); // main fuselage
    m.addWedge(0, 0.48, -0.5, 0.32, 0.18, 0.52, 0.28, 2.1, 2, 0); // cockpit
    m.addBox(1.15, 0, 0.6, 0.65, 0.55, 3.2, 1, 0); // R nacelle
    m.addBox(-1.15, 0, 0.6, 0.65, 0.55, 3.2, 1, 0); // L nacelle
    m.addWing(1.3, 3.6, 0.0, -0.3, 1.4, 0.7, 1.9, 0.20, 0, 0);
    m.addWing(-1.3, -3.6, 0.0, -0.3, 1.4, 0.7, 1.9, 0.20, 0, 0);
    m.addBox(2.2, -0.1, -0.3, 0.24, 0.24, 1.8, 3, 0);
    m.addBox(-2.2, -0.1, -0.3, 0.24, 0.24, 1.8, 3, 0);
    m.exportGltf("assets/models/ship_fighter.gltf", "ship_fighter");
  }

  // 3. Frigate (heavy armored hull + railgun)
  {
    const m = new MeshBuilder();
    m.addWedge(0, 0, 0, 0.95, 0.52, 1.65, 0.95, 6.4, 0, 0); // thick hull
    m.addBox(0, 0.68, 0.3, 1.15, 0.45, 3.0, 2, 0); // bridge tower
    m.addBox(1.85, -0.1, 0.7, 1.0, 0.85, 4.4, 1, 0); // R armor pod
    m.addBox(-1.85, -0.1, 0.7, 1.0, 0.85, 4.4, 1, 0); // L armor pod
    m.addBox(0, 0.18, -2.5, 0.36, 0.34, 3.6, 3, 0); // central railgun barrel
    m.addWing(2.2, 3.9, 0.15, 0.4, 2.2, 1.0, 2.6, 0.28, 0, 0);
    m.addWing(-2.2, -3.9, 0.15, 0.4, 2.2, 1.0, 2.6, 0.28, 0, 0);
    m.exportGltf("assets/models/ship_frigate.gltf", "ship_frigate");
  }

  // 4. Modular Tier Attachments (row 8)
  {
    const m = new MeshBuilder();
    m.addWing(2.4, 4.1, 0.35, 0.3, 1.5, 1.4, 2.2, 0.14, 0, 8);
    m.addWing(-2.4, -4.1, 0.35, 0.3, 1.5, 1.4, 2.2, 0.14, 0, 8);
    m.exportGltf("assets/models/tier_wings_t2.gltf", "tier_wings_t2");
  }
  {
    const m = new MeshBuilder();
    m.addBox(2.6, -0.22, -0.4, 0.26, 0.26, 2.2, 3, 8);
    m.addBox(-2.6, -0.22, -0.4, 0.26, 0.26, 2.2, 3, 8);
    m.addBox(0, 0.78, 0.2, 0.55, 0.22, 1.6, 1, 8);
    m.exportGltf("assets/models/tier_arms_t3.gltf", "tier_arms_t3");
  }
  {
    const m = new MeshBuilder();
    m.addBox(1.25, 0.35, 2.1, 0.55, 0.55, 1.6, 2, 8);
    m.addBox(-1.25, 0.35, 2.1, 0.55, 0.55, 1.6, 2, 8);
    m.exportGltf("assets/models/tier_thrusters_t4.gltf", "tier_thrusters_t4");
  }
  {
    const m = new MeshBuilder();
    m.addBox(0, 0.62, -0.6, 0.42, 0.24, 2.4, 6, 14); // glowing spine strip
    m.addBox(3.4, 0.2, 1.5, 0.18, 0.18, 1.2, 6, 14);
    m.addBox(-3.4, 0.2, 1.5, 0.18, 0.18, 1.2, 6, 14);
    m.exportGltf("assets/models/tier_core_t5.gltf", "tier_core_t5");
  }

  // 5. Asteroids & Hollow Tunnel Asteroid & Station
  {
    const m = new MeshBuilder();
    m.addSphere(0, 0, 0, 1.0, 9, 6, 0, 9, 1.3);
    m.exportGltf("assets/models/asteroid_01.gltf", "asteroid_01");
  }
  {
    const m = new MeshBuilder();
    m.addSphere(0, 0, 0, 1.0, 8, 5, 2, 9, 3.7);
    m.exportGltf("assets/models/asteroid_02.gltf", "asteroid_02");
  }
  {
    const m = new MeshBuilder();
    m.addTorus(0, 0, 0, 1.0, 0.36, 14, 7, 1, 9);
    m.exportGltf("assets/models/asteroid_hollow.gltf", "asteroid_hollow");
  }
  {
    const m = new MeshBuilder();
    m.addTorus(0, 0, 0, 26, 3.5, 20, 8, 4, 9);
    m.addBox(0, 0, 0, 12, 34, 12, 5, 9);
    m.addBox(0, 0, 0, 52, 2.5, 4, 2, 9);
    m.addBox(0, 0, 0, 4, 2.5, 52, 2, 9);
    m.exportGltf("assets/models/station_core.gltf", "station_core");
  }

  // 6. Beacon
  {
    const m = new MeshBuilder();
    m.addSphere(0, 0, 0, 3.2, 6, 3, 3, 14, 0);
    m.addTorus(0, 0, 0, 6.2, 0.55, 16, 6, 3, 14);
    m.exportGltf("assets/models/beacon.gltf", "beacon");
  }

  // 7. Dreadnought Boss + Modules
  {
    const m = new MeshBuilder();
    m.addWedge(0, 0, 0, 10, 6, 22, 12, 130, 0, 10); // massive prow to stern
    m.addBox(0, 12, 22, 16, 10, 30, 1, 10); // command citadel
    m.addBox(22, -2, 10, 10, 8, 70, 2, 10); // port armor wing
    m.addBox(-22, -2, 10, 10, 8, 70, 2, 10); // starboard armor wing
    m.addBox(0, 0, 66, 24, 10, 6, 3, 10); // stern thruster array
    m.exportGltf("assets/models/dreadnought_hull.gltf", "dreadnought_hull");
  }
  {
    const m = new MeshBuilder();
    m.addSphere(0, 0, 0, 4.2, 8, 5, 6, 14, 0);
    m.addBox(0, -3.5, 0, 6, 2.5, 6, 4, 10);
    m.exportGltf("assets/models/dreadnought_gen.gltf", "dreadnought_gen");
  }
  {
    const m = new MeshBuilder();
    m.addBox(0, 0, 0, 4.5, 3.2, 5.2, 4, 10);
    m.addBox(1.1, 0.4, -4.5, 0.8, 0.8, 6.5, 3, 10);
    m.addBox(-1.1, 0.4, -4.5, 0.8, 0.8, 6.5, 3, 10);
    m.exportGltf("assets/models/dreadnought_turret.gltf", "dreadnought_turret");
  }
  {
    const m = new MeshBuilder();
    m.addSphere(0, 0, 0, 7.5, 10, 6, 5, 10, 0);
    m.exportGltf("assets/models/dreadnought_reactor.gltf", "dreadnought_reactor");
  }

  // 8. Projectiles, VFX Sphere, Engine Trail
  {
    const m = new MeshBuilder();
    m.addBox(0, 0, 0, 0.35, 0.35, 4.2, 6, 14);
    m.exportGltf("assets/models/projectile_laser.gltf", "projectile_laser");
  }
  {
    const m = new MeshBuilder();
    m.addWedge(0, 0, 0, 0.1, 0.1, 0.42, 0.42, 2.4, 4, 14);
    m.exportGltf("assets/models/projectile_missile.gltf", "projectile_missile");
  }
  {
    const m = new MeshBuilder();
    m.addSphere(0, 0, 0, 1.0, 10, 6, 6, 14, 0);
    m.exportGltf("assets/models/vfx_sphere.gltf", "vfx_sphere");
  }
  {
    const m = new MeshBuilder();
    m.addWedge(0, 0, 0, 0.32, 0.32, 0.02, 0.02, 4.5, 6, 14);
    m.exportGltf("assets/models/engine_trail.gltf", "engine_trail");
  }
  // 9. Star dome (distant star quads at radius 750m)
  {
    const m = new MeshBuilder();
    const R = 750;
    for (let i = 0; i < 160; i++) {
      // Fibonacci sphere distribution
      const t = (i + 0.5) / 160;
      const phi = Math.acos(1 - 2 * t);
      const theta = Math.PI * (1 + Math.sqrt(5)) * i;
      const nx = Math.sin(phi) * Math.cos(theta);
      const ny = Math.cos(phi);
      const nz = Math.sin(phi) * Math.sin(theta);
      const cx = nx * R, cy = ny * R, cz = nz * R;
      const s = (i % 5 === 0) ? 2.4 : 1.25;
      // Tangent basis
      const up = Math.abs(ny) < 0.9 ? [0, 1, 0] : [1, 0, 0];
      let tx = up[1] * nz - up[2] * ny, ty = up[2] * nx - up[0] * nz, tz = up[0] * ny - up[1] * nx;
      const tl = Math.hypot(tx, ty, tz) || 1;
      tx /= tl; ty /= tl; tz /= tl;
      const bx = ny * tz - nz * ty, by = nz * tx - nx * tz, bz = nx * ty - ny * tx;
      const a = [cx - tx * s - bx * s, cy - ty * s - by * s, cz - tz * s - bz * s];
      const b = [cx + tx * s - bx * s, cy + ty * s - by * s, cz + tz * s - bz * s];
      const c = [cx + tx * s + bx * s, cy + ty * s + by * s, cz + tz * s + bz * s];
      const d = [cx - tx * s + bx * s, cy - ty * s + by * s, cz - tz * s + bz * s];
      const col = (i % 7 === 0) ? 0 : (i % 11 === 0 ? 3 : 6);
      m.addQuad(a, b, c, d, col, 14);
    }
    m.exportGltf("assets/models/star_dome.gltf", "star_dome");
  }

  // 10. Race / tutorial ring gate (axis = +Y, oriented in Lua with quat_from_to)
  {
    const m = new MeshBuilder();
    m.addTorus(0, 0, 0, 9.0, 0.6, 28, 6, 6, 14);
    for (let k = 0; k < 4; k++) {
      const a = (k / 4) * Math.PI * 2 + Math.PI / 4;
      m.addBox(Math.cos(a) * 10.4, 0, Math.sin(a) * 10.4, 1.1, 1.6, 1.1, 6, 14);
    }
    m.exportGltf("assets/models/ring_gate.gltf", "ring_gate");
  }

  // 11. Pirate drone (small spiked orb with a red sensor eye, forward = -Z)
  {
    const m = new MeshBuilder();
    m.addSphere(0, 0, 0, 1.3, 8, 5, 5, 8, 0);
    m.addSphere(0, 0, -1.05, 0.55, 6, 4, 7, 8, 0); // sensor eye
    m.addBox(1.7, 0, 0.2, 1.6, 0.18, 1.2, 1, 8); // R fin
    m.addBox(-1.7, 0, 0.2, 1.6, 0.18, 1.2, 1, 8); // L fin
    m.addBox(0, 1.45, 0.3, 0.2, 1.0, 0.9, 2, 8); // top spike
    m.addBox(0, -1.45, 0.3, 0.2, 1.0, 0.9, 2, 8); // bottom spike
    m.addBox(0, 0, 1.45, 0.7, 0.7, 0.6, 7, 8); // thruster
    m.exportGltf("assets/models/drone.gltf", "drone");
  }

  // 12. Escort freighter (long cargo hauler, forward = -Z)
  {
    const m = new MeshBuilder();
    m.addBox(0, 0, 0, 3.6, 3.0, 24, 0, 8); // spine
    m.addWedge(0, 0.4, -13.5, 1.0, 0.8, 2.0, 1.6, 4.0, 4, 8); // prow
    m.addBox(0, 2.6, -9.5, 2.6, 2.0, 3.4, 2, 8); // bridge
    const cont = [[3, 8], [7, 9], [2, 10], [3, 8], [6, 8]];
    for (let i = 0; i < 5; i++) {
      const z = -6 + i * 3.6;
      const c = cont[i];
      m.addBox(3.2, 0, z, 2.6, 2.6, 3.2, c[0], c[1]);
      m.addBox(-3.2, 0, z, 2.6, 2.6, 3.2, c[0], c[1]);
    }
    m.addBox(1.6, 0, 13.2, 2.0, 2.0, 2.6, 2, 8); // engines
    m.addBox(-1.6, 0, 13.2, 2.0, 2.0, 2.6, 2, 8);
    m.addBox(1.6, 0, 14.6, 1.4, 1.4, 0.4, 6, 8); // engine glow
    m.addBox(-1.6, 0, 14.6, 1.4, 1.4, 0.4, 6, 8);
    m.exportGltf("assets/models/freighter.gltf", "freighter");
  }
}

// ============================================================================
// 4. Lightweight Procedural WAV SFX (22050 Hz, 16-bit mono)
// ============================================================================
function writeWav(relPath, samples) {
  const sampleRate = 22050;
  const dataLen = samples.length * 2;
  const buf = Buffer.alloc(44 + dataLen);
  buf.write("RIFF", 0);
  buf.writeUInt32LE(36 + dataLen, 4);
  buf.write("WAVE", 8);
  buf.write("fmt ", 12);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20); // PCM
  buf.writeUInt16LE(1, 22); // mono
  buf.writeUInt32LE(sampleRate, 24);
  buf.writeUInt32LE(sampleRate * 2, 28);
  buf.writeUInt16LE(2, 32);
  buf.writeUInt16LE(16, 34);
  buf.write("data", 36);
  buf.writeUInt32LE(dataLen, 40);
  for (let i = 0; i < samples.length; i++) {
    const v = Math.max(-1, Math.min(1, samples[i]));
    buf.writeInt16LE(Math.floor(v * 32767), 44 + i * 2);
  }
  const full = path.join(ROOT, relPath);
  fs.mkdirSync(path.dirname(full), { recursive: true });
  fs.writeFileSync(full, buf);
}

function synth(dur, fn) {
  const n = Math.floor(22050 * dur);
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    out[i] = fn(i / 22050, i / n);
  }
  return out;
}

function generateSfx() {
  writeWav("assets/sfx/laser.wav", synth(0.11, (t, p) => {
    const f = 920 - 650 * p;
    return Math.sin(2 * Math.PI * f * t) * (1 - p) * 0.35;
  }));
  writeWav("assets/sfx/kinetic.wav", synth(0.08, (t, p) => {
    const tone = Math.sin(2 * Math.PI * (240 - 150 * p) * t);
    const noise = (Math.random() * 2 - 1) * 0.6;
    return (tone * 0.5 + noise * 0.5) * (1 - p) * 0.35;
  }));
  writeWav("assets/sfx/railgun.wav", synth(0.24, (t, p) => {
    const f = 1400 * Math.exp(-5 * p) + 120;
    const snap = Math.sin(2 * Math.PI * f * t);
    const noise = (Math.random() * 2 - 1) * Math.exp(-8 * p);
    return (snap * 0.7 + noise * 0.4) * (1 - p) * 0.45;
  }));
  writeWav("assets/sfx/missile.wav", synth(0.28, (t, p) => {
    const noise = (Math.random() * 2 - 1) * 0.5;
    const whoosh = Math.sin(2 * Math.PI * (300 + 400 * p) * t) * 0.3;
    return (noise + whoosh) * Math.sin(Math.PI * p) * 0.4;
  }));
  writeWav("assets/sfx/explosion.wav", synth(0.45, (t, p) => {
    const rumble = Math.sin(2 * Math.PI * (90 - 55 * p) * t);
    const noise = (Math.random() * 2 - 1);
    return (rumble * 0.4 + noise * 0.6) * Math.pow(1 - p, 1.6) * 0.55;
  }));
  writeWav("assets/sfx/shield_hit.wav", synth(0.12, (t, p) => {
    return Math.sin(2 * Math.PI * (650 + 280 * Math.sin(p * 12)) * t) * (1 - p) * 0.3;
  }));
  writeWav("assets/sfx/dash.wav", synth(0.22, (t, p) => {
    const f = 180 + 720 * p;
    return (Math.sin(2 * Math.PI * f * t) * 0.6 + (Math.random() * 2 - 1) * 0.3) * (1 - p) * 0.4;
  }));
  writeWav("assets/sfx/emp.wav", synth(0.32, (t, p) => {
    const f = 1200 * (1 - p * 0.75);
    return Math.sin(2 * Math.PI * f * t) * Math.cos(p * 25) * (1 - p) * 0.4;
  }));
  writeWav("assets/sfx/heal.wav", synth(0.26, (t, p) => {
    const f = 440 + 440 * p;
    return Math.sin(2 * Math.PI * f * t) * Math.sin(Math.PI * p) * 0.35;
  }));
  writeWav("assets/sfx/ui_click.wav", synth(0.04, (t, p) => {
    return Math.sin(2 * Math.PI * 880 * t) * (1 - p) * 0.25;
  }));
  writeWav("assets/sfx/lock.wav", synth(0.08, (t, p) => {
    const f = p < 0.45 ? 1080 : 1560;
    const env = Math.sin(Math.PI * p) * (1 - p * 0.4);
    return Math.sin(2 * Math.PI * f * t) * env * 0.28;
  }));
  // Seamless 8s space ambient pad (integer cycles over 8s for zero-click loop)
  writeWav("assets/sfx/ambient.wav", synth(8.0, (t, p) => {
    const w = 2 * Math.PI * p;
    const lfo1 = 0.65 + 0.35 * Math.sin(w * 1);
    const lfo2 = 0.60 + 0.40 * Math.cos(w * 2);
    const lfo3 = 0.55 + 0.45 * Math.sin(w * 3 + 1.1);
    const sub = Math.sin(w * 440) * 0.34;          // 55 Hz (A1)
    const fifth = Math.sin(w * 660) * 0.24 * lfo1; // 82.5 Hz (E2)
    const oct = Math.sin(w * 880) * 0.16 * lfo2;   // 110 Hz (A2)
    const shimmer = Math.sin(w * 1320) * 0.10 * lfo3; // 165 Hz (E3)
    const ninth = Math.sin(w * 1980) * 0.06 * (0.5 + 0.5 * Math.sin(w * 2 + 0.7)); // 247.5 Hz (B3)
    return (sub + fifth + oct + shimmer + ninth) * 0.24;
  }));
  writeWav("assets/sfx/victory.wav", synth(0.85, (t, p) => {
    const notes = [523.25, 659.25, 783.99, 1046.50]; // C5 E5 G5 C6
    const idx = Math.min(3, Math.floor(p * 4));
    const localP = (p * 4) - idx;
    const freq = notes[idx];
    const noteEnv = Math.sin(Math.min(1, localP * 6) * Math.PI * 0.5) * Math.pow(1 - p, 0.75);
    const tone = Math.sin(2 * Math.PI * freq * t) * 0.65 + Math.sin(2 * Math.PI * freq * 1.5 * t) * 0.20;
    const chord = Math.sin(2 * Math.PI * 523.25 * t) * 0.25 + Math.sin(2 * Math.PI * 783.99 * t) * 0.20;
    return (tone + chord * p) * noteEnv * 0.38;
  }));
  writeWav("assets/sfx/defeat.wav", synth(0.85, (t, p) => {
    const notes = [392.00, 349.23, 293.66, 220.00]; // G4 F4 D4 A3
    const idx = Math.min(3, Math.floor(p * 4));
    const freq = notes[idx];
    const env = Math.sin(Math.min(1, p * 12) * Math.PI * 0.5) * Math.pow(1 - p, 1.15);
    const tone = Math.sin(2 * Math.PI * freq * t) * 0.65 + Math.sin(2 * Math.PI * (freq * 0.5) * t) * 0.35;
    return tone * env * 0.38;
  }));
  // Ring gate pass chime (two bright partials)
  writeWav("assets/sfx/ring.wav", synth(0.32, (t, p) => {
    const f = p < 0.35 ? 988 : 1319;
    const env = Math.pow(1 - p, 1.4) * Math.min(1, p * 40);
    return (Math.sin(2 * Math.PI * f * t) * 0.6 + Math.sin(2 * Math.PI * f * 2 * t) * 0.15) * env * 0.38;
  }));
  // Level up arpeggio
  writeWav("assets/sfx/levelup.wav", synth(1.1, (t, p) => {
    const notes = [523.25, 659.25, 783.99, 1046.5, 1318.5];
    const idx = Math.min(4, Math.floor(p * 6));
    const lp = p * 6 - idx;
    const f = notes[idx];
    const env = Math.min(1, lp * 10) * Math.pow(1 - p, 0.6);
    return (Math.sin(2 * Math.PI * f * t) * 0.55 + Math.sin(2 * Math.PI * f * 2.01 * t) * 0.15) * env * 0.4;
  }));
  // Incoming missile / danger alarm (two fast beeps)
  writeWav("assets/sfx/alarm.wav", synth(0.36, (t, p) => {
    const on = (p < 0.4) || (p > 0.55 && p < 0.95);
    if (!on) return 0;
    return Math.sign(Math.sin(2 * Math.PI * 1250 * t)) * 0.16;
  }));
  // Wave incoming horn
  writeWav("assets/sfx/wave.wav", synth(0.9, (t, p) => {
    const f = 110 + 30 * Math.sin(p * Math.PI);
    const env = Math.sin(Math.PI * p);
    return (Math.sin(2 * Math.PI * f * t) * 0.5 + Math.sin(2 * Math.PI * f * 1.5 * t) * 0.3 + Math.sin(2 * Math.PI * f * 2 * t) * 0.2) * env * 0.45;
  }));
  // Afterburner ignition whoosh
  writeWav("assets/sfx/boost.wav", synth(0.35, (t, p) => {
    const noise = (Math.random() * 2 - 1);
    const tone = Math.sin(2 * Math.PI * (120 + 260 * p) * t);
    return (noise * 0.55 + tone * 0.35) * Math.sin(Math.PI * Math.min(1, p * 1.4)) * 0.32;
  }));
  // Objective complete (major third up)
  writeWav("assets/sfx/objective.wav", synth(0.55, (t, p) => {
    const f = p < 0.45 ? 659.25 : 830.6;
    const env = Math.pow(1 - p, 0.9) * Math.min(1, p * 30);
    return (Math.sin(2 * Math.PI * f * t) * 0.5 + Math.sin(2 * Math.PI * f * 0.5 * t) * 0.25) * env * 0.4;
  }));
  // Denied buzz
  writeWav("assets/sfx/error.wav", synth(0.18, (t, p) => {
    return Math.sign(Math.sin(2 * Math.PI * 140 * t)) * (1 - p) * 0.14;
  }));
  // Reward / coin tick
  writeWav("assets/sfx/coin.wav", synth(0.16, (t, p) => {
    const f = p < 0.3 ? 1568 : 2093;
    return Math.sin(2 * Math.PI * f * t) * Math.pow(1 - p, 1.5) * 0.28;
  }));
  // Hit confirm tick (very short, high)
  writeWav("assets/sfx/hit.wav", synth(0.05, (t, p) => {
    return Math.sin(2 * Math.PI * 2400 * t) * Math.pow(1 - p, 2) * 0.22;
  }));
  // Kill confirm (punchy low + high ping)
  writeWav("assets/sfx/kill.wav", synth(0.3, (t, p) => {
    const low = Math.sin(2 * Math.PI * (160 - 90 * p) * t) * Math.pow(1 - p, 2);
    const ping = Math.sin(2 * Math.PI * 1760 * t) * Math.pow(1 - p, 3);
    return (low * 0.5 + ping * 0.3) * 0.5;
  }));
}

// ============================================================================
// 5. UI Atlas Images (sharp procedural vector PNGs)
// ============================================================================
function makeCanvas(w, h) {
  const data = Buffer.alloc(w * h * 4);
  return {
    w, h, data,
    set(x, y, r, g, b, a) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      const ix = Math.floor(x), iy = Math.floor(y);
      const idx = (iy * w + ix) * 4;
      const alpha = a / 255;
      const inv = 1 - alpha;
      data[idx] = Math.round(r * alpha + data[idx] * inv);
      data[idx + 1] = Math.round(g * alpha + data[idx + 1] * inv);
      data[idx + 2] = Math.round(b * alpha + data[idx + 2] * inv);
      data[idx + 3] = Math.min(255, Math.round(a + data[idx + 3] * inv));
    },
    circle(cx, cy, rOuter, rInner, rgb, alpha = 255) {
      for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
          const d = Math.hypot(x + 0.5 - cx, y + 0.5 - cy);
          if (d <= rOuter && d >= rInner) {
            const edge = Math.min(1, rOuter - d, d - rInner + 1);
            this.set(x, y, rgb[0], rgb[1], rgb[2], Math.max(0, Math.min(255, edge * alpha)));
          }
        }
      }
    },
    rect(x0, y0, rw, rh, rad, rgb, alpha = 255) {
      for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
          const px = x + 0.5, py = y + 0.5;
          const cx = Math.max(x0 + rad, Math.min(x0 + rw - rad, px));
          const cy = Math.max(y0 + rad, Math.min(y0 + rh - rad, py));
          const d = Math.hypot(px - cx, py - cy);
          if (d <= rad + 0.5) {
            const a = Math.min(1, rad + 0.5 - d) * alpha;
            this.set(x, y, rgb[0], rgb[1], rgb[2], a);
          }
        }
      }
    },
  };
}

function generateUiAssets() {
  // White 8x8 pixel for tinted bars/panels
  {
    // Filled directly: rect() with radius 0 yields alpha 0.5 (edge falloff), which
    // made every "white" box (bars, overlays) half transparent.
    const c = makeCanvas(16, 16);
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) c.set(x, y, 255, 255, 255, 255);
    writePng("assets/ui/white.png", 16, 16, c.data);
  }
  // Rounded panel (64x64, 9-slice friendly)
  {
    const c = makeCanvas(64, 64);
    c.rect(1, 1, 62, 62, 12, [255, 255, 255], 255);
    writePng("assets/ui/panel_rounded.png", 64, 64, c.data);
  }
  // Soft lock reticle ring (128x128)
  {
    const c = makeCanvas(128, 128);
    c.circle(64, 64, 58, 53, [255, 255, 255], 220);
    c.circle(64, 64, 5, 0, [255, 255, 255], 230);
    writePng("assets/ui/reticle.png", 128, 128, c.data);
  }
  // Target lock diamond / bracket (64x64)
  {
    const c = makeCanvas(64, 64);
    c.circle(32, 32, 28, 23, [255, 255, 255], 255);
    writePng("assets/ui/lock_ring.png", 64, 64, c.data);
  }
  // Lead pip (32x32)
  {
    const c = makeCanvas(32, 32);
    c.circle(16, 16, 13, 9, [255, 255, 255], 255);
    c.circle(16, 16, 4, 0, [255, 255, 255], 255);
    writePng("assets/ui/lead_pip.png", 32, 32, c.data);
  }
  // Touch stick base & knob
  {
    const c = makeCanvas(160, 160);
    c.circle(80, 80, 76, 70, [255, 255, 255], 180);
    c.circle(80, 80, 70, 0, [255, 255, 255], 40);
    writePng("assets/ui/stick_base.png", 160, 160, c.data);
  }
  {
    const c = makeCanvas(80, 80);
    c.circle(40, 40, 36, 0, [255, 255, 255], 220);
    writePng("assets/ui/stick_knob.png", 80, 80, c.data);
  }
  // Circle button (96x96)
  {
    const c = makeCanvas(96, 96);
    c.circle(48, 48, 45, 0, [255, 255, 255], 255);
    writePng("assets/ui/btn_circle.png", 96, 96, c.data);
  }
  // Triangle arrow (off-screen indicator, 32x32 pointing up)
  {
    const c = makeCanvas(32, 32);
    for (let y = 3; y <= 28; y++) {
      const half = ((y - 3) / 25) * 12;
      for (let x = 16 - half; x <= 16 + half; x++) {
        c.set(x, y, 255, 255, 255, 255);
      }
    }
    writePng("assets/ui/arrow_up.png", 32, 32, c.data);
  }

  // Hit marker X-crosshair (64x64)
  {
    const c = makeCanvas(64, 64);
    for (let y = 0; y < 64; y++) {
      for (let x = 0; x < 64; x++) {
        const dx = Math.abs(x + 0.5 - 32);
        const dy = Math.abs(y + 0.5 - 32);
        const r = Math.hypot(dx, dy);
        const diagDist = Math.abs(dx - dy) / Math.SQRT2;
        if (r >= 9 && r <= 26 && diagDist <= 2.2) {
          const edge = Math.min(1, 2.2 - diagDist + 0.5, r - 8.5, 26.5 - r);
          c.set(x, y, 255, 255, 255, Math.max(0, Math.min(255, edge * 255)));
        }
      }
    }
    writePng("assets/ui/hit_marker.png", 64, 64, c.data);
  }

  // Five-point star (mission rating)
  {
    const c = makeCanvas(64, 64);
    const pts = [];
    for (let i = 0; i < 10; i++) {
      const a = -Math.PI / 2 + i * Math.PI / 5;
      const r = (i % 2 === 0) ? 30 : 12.5;
      pts.push([32 + Math.cos(a) * r, 33 + Math.sin(a) * r]);
    }
    const inside = (x, y) => {
      let ins = false;
      for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
        const [xi, yi] = pts[i], [xj, yj] = pts[j];
        if (((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) ins = !ins;
      }
      return ins;
    };
    for (let y = 0; y < 64; y++) {
      for (let x = 0; x < 64; x++) {
        let cov = 0;
        for (let sy = 0; sy < 4; sy++) for (let sx = 0; sx < 4; sx++) {
          if (inside(x + (sx + 0.5) / 4, y + (sy + 0.5) / 4)) cov++;
        }
        if (cov > 0) c.set(x, y, 255, 255, 255, Math.round(cov / 16 * 255));
      }
    }
    writePng("assets/ui/star.png", 64, 64, c.data);
  }
  // Radar scope (256x256): filled disc, range rings, cross lines
  {
    const c = makeCanvas(256, 256);
    c.circle(128, 128, 126, 0, [255, 255, 255], 46);
    c.circle(128, 128, 126, 122, [255, 255, 255], 200);
    c.circle(128, 128, 85, 83, [255, 255, 255], 90);
    c.circle(128, 128, 43, 41, [255, 255, 255], 90);
    for (let i = 8; i < 248; i++) {
      c.set(i, 128, 255, 255, 255, 60);
      c.set(128, i, 255, 255, 255, 60);
    }
    writePng("assets/ui/radar.png", 256, 256, c.data);
  }
  // Damage / low-hull vignette (transparent centre, opaque edges)
  {
    const c = makeCanvas(128, 128);
    for (let y = 0; y < 128; y++) {
      for (let x = 0; x < 128; x++) {
        const dx = (x + 0.5 - 64) / 64, dy = (y + 0.5 - 64) / 64;
        const d = Math.sqrt(dx * dx + dy * dy) / Math.SQRT2;
        const t = Math.max(0, Math.min(1, (d - 0.45) / 0.55));
        const a = t * t * (3 - 2 * t);
        c.set(x, y, 255, 255, 255, Math.round(a * 255));
      }
    }
    writePng("assets/ui/vignette.png", 128, 128, c.data);
  }
  // Padlock (locked content)
  {
    const c = makeCanvas(48, 48);
    c.circle(24, 19, 11, 7, [255, 255, 255], 255);
    for (let y = 0; y < 48; y++) for (let x = 0; x < 48; x++) {
      if (y > 19) c.set(x, y, 0, 0, 0, 0);
    }
    c.rect(10, 20, 28, 22, 4, [255, 255, 255], 255);
    c.circle(24, 29, 3.2, 0, [20, 30, 45], 255);
    c.rect(22.5, 30, 3, 7, 1, [20, 30, 45], 255);
    writePng("assets/ui/padlock.png", 48, 48, c.data);
  }
  // Soft glow dot (radar blips, banners)
  {
    const c = makeCanvas(32, 32);
    for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) {
      const d = Math.hypot(x + 0.5 - 16, y + 0.5 - 16) / 16;
      if (d < 1) {
        const a = d < 0.55 ? 1 : Math.pow(1 - (d - 0.55) / 0.45, 1.6);
        c.set(x, y, 255, 255, 255, Math.round(a * 255));
      }
    }
    writePng("assets/ui/dot.png", 32, 32, c.data);
  }

  // Generate ui.atlas
  const images = [
    "white", "panel_rounded", "reticle", "lock_ring",
    "lead_pip", "stick_base", "stick_knob", "btn_circle", "arrow_up",
    "hit_marker", "star", "radar", "vignette", "padlock", "dot"
  ];
  const atlas = images.map(n => `images {\n  image: "/assets/ui/${n}.png"\n}`).join("\n") +
    "\nmargin: 2\nextrude_borders: 2\ninner_padding: 0\n";
  fs.mkdirSync(path.join(ROOT, "assets/atlases"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "assets/atlases/ui.atlas"), atlas, "utf8");
}

ensureDir("assets/fonts");
ensureDir("assets/textures");
ensureDir("assets/models");
ensureDir("assets/sfx");
ensureDir("assets/ui");
ensureDir("assets/atlases");

generateFont();
generatePalette();
generateModels();
generateSfx();
generateUiAssets();

console.log("Generated font, palette_256.png, glTF models, WAV SFX, and UI atlas.");
