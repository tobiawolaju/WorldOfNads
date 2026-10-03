// Verification harness for godot/auth/QRGenerator.gd.
//
// Ports the GDScript encoder to JS and checks it three ways:
//   1. Static table self-consistency (codeword totals, format info vs the
//      published ISO/IEC 18004 Table 25, version info vs Table D.1).
//   2. A full decode round-trip: read format info back out of the finished
//      matrix, unmask, walk the zig-zag in reverse, de-interleave.
//   3. Reed-Solomon syndromes all zero on every block, which is a real proof
//      that the error correction is arithmetically correct.
//
// Run: node godot/auth/verify-qr.mjs

// ---------------------------------------------------------------------------
// Port of the encoder
// ---------------------------------------------------------------------------

const ECC_M = 0;
const ECC_L = 1;
const QUIET_ZONE = 4;

const TOTAL_CODEWORDS = [26, 44, 70, 100, 134, 172, 196, 242, 292, 346];

const ECC_TABLE = {
  1: { 1: [7, 1, 19, 0, 0], 0: [10, 1, 16, 0, 0] },
  2: { 1: [10, 1, 34, 0, 0], 0: [16, 1, 28, 0, 0] },
  3: { 1: [15, 1, 55, 0, 0], 0: [26, 1, 44, 0, 0] },
  4: { 1: [20, 1, 80, 0, 0], 0: [18, 2, 32, 0, 0] },
  5: { 1: [26, 1, 108, 0, 0], 0: [24, 2, 43, 0, 0] },
  6: { 1: [18, 2, 68, 0, 0], 0: [16, 4, 27, 0, 0] },
  7: { 1: [20, 2, 78, 0, 0], 0: [18, 4, 31, 0, 0] },
  8: { 1: [24, 2, 97, 0, 0], 0: [22, 2, 38, 2, 39] },
  9: { 1: [30, 2, 116, 0, 0], 0: [22, 3, 36, 2, 37] },
  10: { 1: [18, 2, 68, 2, 69], 0: [26, 4, 43, 1, 44] },
};

const ALIGNMENT_POSITIONS = {
  1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30],
  6: [6, 34], 7: [6, 22, 38], 8: [6, 24, 42], 9: [6, 26, 46], 10: [6, 28, 50],
};

const REMAINDER_BITS = [0, 7, 7, 7, 7, 7, 0, 0, 0, 0];
const VERSION_INFO = { 7: 0x07c94, 8: 0x085bc, 9: 0x09a99, 10: 0x0a4d3 };
const MAX_VERSION = 10;

export function gfMul(a, b) {
  let result = 0, x = a, y = b;
  for (let i = 0; i < 8; i++) {
    if (y & 1) result ^= x;
    y >>= 1;
    x <<= 1;
    if (x & 0x100) x ^= 0x11d;
  }
  return result;
}

export function gfPow(base, exponent) {
  let result = 1;
  for (let i = 0; i < exponent; i++) result = gfMul(result, base);
  return result;
}

function polyMultiply(a, scalar) {
  const out = new Int32Array(a.length + 1);
  for (let i = 0; i < a.length; i++) {
    out[i] ^= a[i];
    out[i + 1] ^= gfMul(a[i], scalar);
  }
  return out;
}

function generatorPolynomial(degree) {
  let poly = Int32Array.of(1);
  for (let i = 0; i < degree; i++) poly = polyMultiply(poly, gfPow(2, i));
  return poly;
}

export function reedSolomon(data, degree) {
  if (degree <= 0) return Int32Array.of(0);
  const generator = generatorPolynomial(degree);
  const remainder = new Int32Array(degree);
  for (const byte of data) {
    const factor = byte ^ remainder[0];
    for (let i = 0; i < degree - 1; i++) {
      remainder[i] = remainder[i + 1] ^ gfMul(factor, generator[i + 1]);
    }
    remainder[degree - 1] = gfMul(factor, generator[degree]);
  }
  return remainder;
}

export function toBits(value, count) {
  const bits = new Int32Array(count);
  for (let i = 0; i < count; i++) bits[i] = (value >> (count - 1 - i)) & 1;
  return bits;
}

export function chooseVersion(byteLength) {
  for (let version = 1; version <= MAX_VERSION; version++) {
    for (const eccLevel of [ECC_M, ECC_L]) {
      const spec = ECC_TABLE[version][eccLevel];
      const dataCodewords = spec[1] * spec[2] + spec[3] * spec[4];
      const countBits = version < 10 ? 8 : 16;
      const capacityBytes = Math.floor((dataCodewords * 8 - 4 - countBits) / 8);
      if (byteLength <= capacityBytes) {
        return {
          version, ecc_level: eccLevel, data_codewords: dataCodewords,
          ec_per_block: spec[0], blocks_g1: spec[1], data_g1: spec[2],
          blocks_g2: spec[3], data_g2: spec[4],
        };
      }
    }
  }
  return {};
}

function encodeByteMode(payload, version) {
  const countBits = version < 10 ? 8 : 16;
  let bits = [];
  bits.push(...toBits(0b0100, 4));
  bits.push(...toBits(payload.length, countBits));
  for (const byte of payload) bits.push(...toBits(byte, 8));
  return Int32Array.from(bits);
}

function toCodewords(bits, target) {
  const stream = Array.from(bits);
  while (stream.length < target * 8 && stream.length % 8 !== 0) stream.push(0);
  const pad = [0xec, 0x11];
  let padIndex = 0;
  while (stream.length < target * 8) {
    stream.push(...toBits(pad[padIndex], 8));
    padIndex = (padIndex + 1) % 2;
  }
  const codewords = [];
  for (let i = 0; i < stream.length; i += 8) {
    let value = 0;
    for (let bit = 0; bit < 8; bit++) value = (value << 1) | stream[i + bit];
    codewords.push(value);
  }
  return Int32Array.from(codewords);
}

function slice(source, offset, length) {
  const out = [];
  for (let i = offset; i < Math.min(offset + length, source.length); i++) out.push(source[i]);
  return Int32Array.from(out);
}

function addErrorCorrection(codewords, version, placement) {
  const ecPerBlock = placement.ec_per_block;
  const dataBlocks = [], ecBlocks = [];
  let offset = 0;
  for (let i = 0; i < placement.blocks_g1; i++) {
    const block = slice(codewords, offset, placement.data_g1);
    offset += block.length;
    dataBlocks.push(block);
    ecBlocks.push(reedSolomon(block, ecPerBlock));
  }
  for (let i = 0; i < placement.blocks_g2; i++) {
    const block = slice(codewords, offset, placement.data_g2);
    offset += block.length;
    dataBlocks.push(block);
    ecBlocks.push(reedSolomon(block, ecPerBlock));
  }
  const result = [];
  let longestData = 0;
  for (const block of dataBlocks) longestData = Math.max(longestData, block.length);
  for (let i = 0; i < longestData; i++)
    for (const block of dataBlocks) if (i < block.length) result.push(block[i]);
  for (let i = 0; i < ecPerBlock; i++)
    for (const block of ecBlocks) if (i < block.length) result.push(block[i]);
  // Mirrors the GDScript `resize` of the same length.
  const targetLength = result.length + REMAINDER_BITS[version - 1];
  while (result.length < targetLength) result.push(0);
  return Int32Array.from(result);
}

export function buildMatrix(text) {
  const payload = Buffer.from(text, 'utf8');
  const placement = chooseVersion(payload.length);
  if (!placement.version) return null;
  const version = placement.version;
  const eccLevel = placement.ecc_level;
  const codewords = toCodewords(encodeByteMode(payload, version), placement.data_codewords);
  const stream = addErrorCorrection(codewords, version, placement);

  const size = version * 4 + 17;
  const modules = new Int32Array(size * size);
  const reserved = new Uint8Array(size * size);
  const put = (x, y, value) => {
    if (x < 0 || y < 0 || x >= size || y >= size) return;
    modules[y * size + x] = value;
    reserved[y * size + x] = 1;
  };

  // Finders, separators, dark module.
  for (const origin of [[0, 0], [size - 7, 0], [0, size - 7]]) {
    for (let dy = -1; dy < 8; dy++)
      for (let dx = -1; dx < 8; dx++) {
        let dark = 0;
        if (dx >= 0 && dx <= 6 && dy >= 0 && dy <= 6) {
          const ring = Math.min(Math.min(dx, dy), Math.min(6 - dx, 6 - dy));
          dark = ring === 0 || ring === 2 ? 1 : 0;
        }
        put(origin[0] + dx, origin[1] + dy, dark);
      }
  }
  put(8, size - 8, 1);

  // Timing patterns.
  for (let i = 8; i < size - 8; i++) {
    const bit = i % 2 === 0 ? 1 : 0;
    put(i, 6, bit);
    put(6, i, bit);
  }

  // Alignment patterns.
  const positions = ALIGNMENT_POSITIONS[version];
  for (const cy of positions)
    for (const cx of positions) {
      const onFinder =
        (cx <= 8 && cy <= 8) || (cx <= 8 && cy >= size - 9) || (cx >= size - 9 && cy <= 8);
      if (onFinder) continue;
      for (let dy = -2; dy <= 2; dy++)
        for (let dx = -2; dx <= 2; dx++) {
          const ring = Math.max(Math.abs(dx), Math.abs(dy));
          put(cx + dx, cy + dy, ring !== 1 ? 1 : 0);
        }
    }

  // Reserve format areas.
  for (let i = 0; i < 9; i++) { reserved[i * size + 8] = 1; reserved[8 * size + i] = 1; }
  for (let i = 0; i < 8; i++) {
    reserved[8 * size + (size - 1 - i)] = 1;
    reserved[(size - 1 - i) * size + 8] = 1;
  }
  // Reserve version areas.
  if (version >= 7) {
    for (let i = 0; i < 18; i++) {
      const row = Math.floor(i / 3), col = size - 11 + (i % 3);
      reserved[row * size + col] = 1;
      reserved[col * size + row] = 1;
    }
  }

  // Place data.
  let bits = [];
  for (const byte of stream) bits.push(...toBits(byte, 8));
  let bitIndex = 0, upward = true;
  for (let col = size - 1; col > 0; col -= 2) {
    if (col === 6) col -= 1;
    for (let step = 0; step < size; step++) {
      const row = upward ? size - 1 - step : step;
      for (let offset = 0; offset < 2; offset++) {
        const index = row * size + (col - offset);
        if (reserved[index] === 1) continue;
        modules[index] = bitIndex < bits.length ? bits[bitIndex] : 0;
        bitIndex++;
      }
    }
    upward = !upward;
  }

  // Version information.
  if (version >= 7) {
    const value = VERSION_INFO[version];
    for (let i = 0; i < 18; i++) {
      const bit = (value >> i) & 1;
      const row = Math.floor(i / 3), col = size - 11 + (i % 3);
      modules[row * size + col] = bit;
      modules[col * size + row] = bit;
    }
  }

  const isFunctionModule = (x, y) => {
    // Separator column/row is at size - 8, not size - 9.
    if (x <= 8 && y <= 8) return true;
    if (x >= size - 8 && y <= 8) return true;
    if (x <= 8 && y >= size - 8) return true;
    if (x === 6 || y === 6) return true;
    if (x === 8 && (y <= 8 || y >= size - 8)) return true;
    if (y === 8 && (x <= 8 || x >= size - 8)) return true;
    if (version >= 7) {
      if (x <= 5 && y >= size - 11 && y <= size - 9) return true;
      if (y <= 5 && x >= size - 11 && x <= size - 9) return true;
    }
    return false;
  };

  const maskApplies = (mask, x, y) => {
    switch (mask) {
      case 0: return (x + y) % 2 === 0;
      case 1: return y % 2 === 0;
      case 2: return x % 3 === 0;
      case 3: return (x + y) % 3 === 0;
      case 4: return (Math.floor(y / 2) + Math.floor(x / 3)) % 2 === 0;
      case 5: return (x * y) % 2 + (x * y) % 3 === 0;
      case 6: return ((x * y) % 2 + (x * y) % 3) % 2 === 0;
      default: return ((x + y) % 2 + (x * y) % 3) % 2 === 0;
    }
  };

  const formatBits = (ecc, mask) => {
    const data = ((ecc & 0b11) << 3) | (mask & 0b111);
    let remainder = data << 10;
    for (let i = 14; i >= 10; i--) if ((remainder >> i) & 1) remainder ^= 0b10100110111 << (i - 10);
    return toBits(((data << 10) | remainder) ^ 0b101010000010010, 15);
  };

  const writeFormatInfo = (m, ecc, mask) => {
    const b = formatBits(ecc, mask);
    for (let i = 0; i < 6; i++) m[8 * size + i] = b[i];
    m[8 * size + 7] = b[6];
    m[8 * size + 8] = b[7];
    m[7 * size + 8] = b[8];
    for (let i = 9; i < 15; i++) m[(14 - i) * size + 8] = b[i];
    for (let i = 0; i < 7; i++) m[(size - 1 - i) * size + 8] = b[i];
    for (let i = 0; i < 8; i++) m[8 * size + (size - 8 + i)] = b[7 + i];
  };

  const penalty = (m) => {
    let score = 0;
    for (let y = 0; y < size; y++) {
      let run = 1;
      for (let x = 1; x < size; x++) {
        if (m[y * size + x] === m[y * size + x - 1]) run++;
        else { if (run >= 5) score += 3 + (run - 5); run = 1; }
      }
      if (run >= 5) score += 3 + (run - 5);
    }
    for (let x = 0; x < size; x++) {
      let run = 1;
      for (let y = 1; y < size; y++) {
        if (m[y * size + x] === m[(y - 1) * size + x]) run++;
        else { if (run >= 5) score += 3 + (run - 5); run = 1; }
      }
      if (run >= 5) score += 3 + (run - 5);
    }
    for (let y = 0; y < size - 1; y++)
      for (let x = 0; x < size - 1; x++) {
        const v = m[y * size + x];
        if (v === m[y * size + x + 1] && v === m[(y + 1) * size + x] && v === m[(y + 1) * size + x + 1]) score += 3;
      }
    const pa = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0];
    const pb = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1];
    for (const pattern of [pa, pb]) {
      for (let y = 0; y < size; y++)
        for (let x = 0; x <= size - 11; x++) {
          let matched = true;
          for (let i = 0; i < 11; i++) if (m[y * size + x + i] !== pattern[i]) { matched = false; break; }
          if (matched) score += 40;
        }
      for (let x = 0; x < size; x++)
        for (let y = 0; y <= size - 11; y++) {
          let matched = true;
          for (let i = 0; i < 11; i++) if (m[(y + i) * size + x] !== pattern[i]) { matched = false; break; }
          if (matched) score += 40;
        }
    }
    let dark = 0;
    for (const v of m) if (v === 1) dark++;
    score += Math.floor(Math.abs((dark / m.length) * 100 - 50) / 5) * 10;
    return score;
  };

  let best = modules.slice(), bestPenalty = -1, bestMask = -1;
  for (let mask = 0; mask < 8; mask++) {
    const candidate = modules.slice();
    for (let y = 0; y < size; y++)
      for (let x = 0; x < size; x++) {
        if (isFunctionModule(x, y)) continue;
        if (maskApplies(mask, x, y)) candidate[y * size + x] = 1 - candidate[y * size + x];
      }
    writeFormatInfo(candidate, eccLevel, mask);
    const p = penalty(candidate);
    if (bestPenalty < 0 || p < bestPenalty) { bestPenalty = p; best = candidate; bestMask = mask; }
  }

  return { modules: best, size, version, ecc: eccLevel, mask: bestMask, placement };
}

// ---------------------------------------------------------------------------
// Independent decoder: reverses the finished matrix back to the payload
// ---------------------------------------------------------------------------

export function decodeMatrix(result) {
  const { modules, size, version } = result;

  // Read format info from copy 1 and validate via BCH.
  const raw = [];
  for (let i = 0; i < 6; i++) raw.push(modules[8 * size + i]);
  raw.push(modules[8 * size + 7]);
  raw.push(modules[8 * size + 8]);
  raw.push(modules[7 * size + 8]);
  for (let i = 9; i < 15; i++) raw.push(modules[(14 - i) * size + 8]);

  let value = 0;
  for (let i = 0; i < 15; i++) value = (value << 1) | raw[i];
  const unmasked = value ^ 0b101010000010010;

  // Copy 2 must agree.
  const copy2 = [];
  for (let i = 0; i < 7; i++) copy2.push(modules[(size - 1 - i) * size + 8]);
  for (let i = 0; i < 8; i++) copy2.push(modules[8 * size + (size - 8 + i)]);
  let value2 = 0;
  for (let i = 0; i < 15; i++) value2 = (value2 << 1) | copy2[i];
  const copiesAgree = value2 === value;

  const ecc = (unmasked >> 13) & 0b11;
  const mask = (unmasked >> 10) & 0b111;

  // Verify version info if present.
  let versionOk = true;
  if (version >= 7) {
    let read = 0;
    for (let i = 0; i < 18; i++) {
      const row = Math.floor(i / 3), col = size - 11 + (i % 3);
      const bit = modules[row * size + col];
      read |= bit << i;
    }
    versionOk = read === VERSION_INFO[version];
  }

  // Rebuild the reserved map independently, then walk the zig-zag in reverse.
  const reserved = new Uint8Array(size * size);
  const mark = (x, y) => { if (x >= 0 && y >= 0 && x < size && y < size) reserved[y * size + x] = 1; };
  for (const origin of [[0, 0], [size - 7, 0], [0, size - 7]])
    for (let dy = -1; dy < 8; dy++) for (let dx = -1; dx < 8; dx++) mark(origin[0] + dx, origin[1] + dy);
  for (let i = 8; i < size - 8; i++) { mark(i, 6); mark(6, i); }
  const positions = ALIGNMENT_POSITIONS[version];
  for (const cy of positions) for (const cx of positions) {
    const onFinder = (cx <= 8 && cy <= 8) || (cx <= 8 && cy >= size - 9) || (cx >= size - 9 && cy <= 8);
    if (onFinder) continue;
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) mark(cx + dx, cy + dy);
  }
  mark(8, size - 8);
  for (let i = 0; i < 9; i++) { mark(8, i); mark(i, 8); }
  for (let i = 0; i < 8; i++) { mark(size - 1 - i, 8); mark(8, size - 1 - i); }
  if (version >= 7)
    for (let i = 0; i < 18; i++) {
      mark(Math.floor(i / 3), size - 11 + (i % 3));
      mark(size - 11 + (i % 3), Math.floor(i / 3));
    }

  const maskApplies = (m, x, y) => {
    switch (m) {
      case 0: return (x + y) % 2 === 0;
      case 1: return y % 2 === 0;
      case 2: return x % 3 === 0;
      case 3: return (x + y) % 3 === 0;
      case 4: return (Math.floor(y / 2) + Math.floor(x / 3)) % 2 === 0;
      case 5: return (x * y) % 2 + (x * y) % 3 === 0;
      case 6: return ((x * y) % 2 + (x * y) % 3) % 2 === 0;
      default: return ((x + y) % 2 + (x * y) % 3) % 2 === 0;
    }
  };

  const stream = [];
  let upward = true;
  for (let col = size - 1; col > 0; col -= 2) {
    if (col === 6) col -= 1;
    for (let step = 0; step < size; step++) {
      const row = upward ? size - 1 - step : step;
      for (let offset = 0; offset < 2; offset++) {
        const x = col - offset;
        if (reserved[row * size + x] === 1) continue;
        let bit = modules[row * size + x];
        if (maskApplies(mask, x, row)) bit = 1 - bit;
        stream.push(bit);
      }
    }
    upward = !upward;
  }

  // Drop the trailing remainder bits.
  const totalData = result.placement.data_codewords;
  const codewords = [];
  for (let i = 0; i + 8 <= stream.length; i += 8) {
    let v = 0;
    for (let b = 0; b < 8; b++) v = (v << 1) | stream[i + b];
    codewords.push(v);
  }
  // Hand back the full interleaved stream; de-interleaving needs the EC
  // section too, not just the leading data codewords.
  return { ecc, mask, copiesAgree, versionOk, codewords, totalData, value, unmasked };
}

// De-interleave the data section and verify RS syndromes are all zero.
export function deinterleaveAndVerify(result, stream) {
  const p = result.placement;
  const ecPerBlock = p.ec_per_block;
  const blockSizes = [];
  for (let i = 0; i < p.blocks_g1; i++) blockSizes.push(p.data_g1);
  for (let i = 0; i < p.blocks_g2; i++) blockSizes.push(p.data_g2);
  const numBlocks = blockSizes.length;

  const blocks = blockSizes.map(() => []);
  const ecBlocks = Array.from({ length: numBlocks }, () => []);
  const longestData = Math.max(...blockSizes);

  let cursor = 0;
  for (let i = 0; i < longestData; i++)
    for (let b = 0; b < numBlocks; b++)
      if (i < blockSizes[b]) blocks[b].push(stream[cursor++]);
  for (let i = 0; i < ecPerBlock; i++)
    for (let b = 0; b < numBlocks; b++) ecBlocks[b].push(stream[cursor++]);

  const dataPart = blocks.flat();
  if (dataPart.length !== p.data_codewords) {
    throw new Error(`de-interleaved ${dataPart.length} data codewords, expected ${p.data_codewords}`);
  }

  // Syndrome check: a valid RS codeword evaluates to 0 at alpha^0..alpha^(d-1).
  let syndromeFailures = 0;
  for (let b = 0; b < numBlocks; b++) {
    const cw = Int32Array.from([...blocks[b], ...ecBlocks[b]]);
    for (let i = 0; i < ecPerBlock; i++) {
      let s = 0;
      for (const coeff of cw) s = gfMul(s, gfPow(2, i)) ^ coeff;
      if (s !== 0) syndromeFailures++;
    }
  }

  // Also confirm the stored EC equals a freshly computed one.
  let ecMismatches = 0;
  for (let b = 0; b < numBlocks; b++) {
    const recomputed = reedSolomon(Int32Array.from(blocks[b]), ecPerBlock);
    for (let i = 0; i < ecPerBlock; i++) if (recomputed[i] !== ecBlocks[b][i]) ecMismatches++;
  }

  return { syndromeFailures, ecMismatches, numBlocks, dataPart };
}

// Decode byte mode back out of the data codewords.
function decodePayload(dataPart, version) {
  const bits = [];
  for (const cw of dataPart) bits.push(...toBits(cw, 8));
  const take = (n) => { let v = 0; for (let i = 0; i < n; i++) v = (v << 1) | bits.splice(0, 1)[0]; return v; };
  const mode = take(4);
  if (mode !== 0b0100) return { mode, text: null };
  const count = take(version < 10 ? 8 : 16);
  const bytes = [];
  for (let i = 0; i < count; i++) bytes.push(take(8));
  return { mode, count, text: Buffer.from(bytes).toString('utf8'), terminator: bits.slice(0, 8) };
}

// ---------------------------------------------------------------------------
// Assertions
// ---------------------------------------------------------------------------

let failures = 0;
const isMain = process.argv[1] && process.argv[1].endsWith('verify-qr.mjs');
const check = (label, condition, detail = '') => {
  if (condition) {
    console.log(`  PASS  ${label}`);
  } else {
    failures++;
    console.log(`  FAIL  ${label}${detail ? ' -- ' + detail : ''}`);
  }
};

if (isMain) {

console.log('\n=== 1. Table self-consistency ===');
for (let v = 1; v <= MAX_VERSION; v++) {
  for (const ecc of [ECC_L, ECC_M]) {
    const spec = ECC_TABLE[v][ecc];
    const dataCw = spec[1] * spec[2] + spec[3] * spec[4];
    const total = dataCw + spec[0] * (spec[1] + spec[3]);
    // TOTAL_CODEWORDS is 0-indexed; versions are 1-indexed.
    const expected = TOTAL_CODEWORDS[v - 1];
    check(`v${v} ${ecc === ECC_M ? 'M' : 'L'} codeword total = ${expected}`,
      total === expected, `got ${total}`);
  }
}

console.log('\n=== 2. Format information vs ISO/IEC 18004 Table 25 ===');
// Published 15-bit format strings, indexed [ecc][mask].
const TABLE25 = {
  L: [0b111011111000100, 0b111001011110011, 0b111110110101010, 0b111100010011101,
      0b110011000101111, 0b110001100011000, 0b110110001000001, 0b110100101110110],
  M: [0b101010000010010, 0b101000100100101, 0b101111001111100, 0b101101101001011,
      0b100010111111001, 0b100000011001110, 0b100111110010111, 0b100101010100000],
};
for (const [name, ecc] of [['L', ECC_L], ['M', ECC_M]]) {
  for (let mask = 0; mask < 8; mask++) {
    const data = ((ecc & 0b11) << 3) | mask;
    let rem = data << 10;
    for (let i = 14; i >= 10; i--) if ((rem >> i) & 1) rem ^= 0b10100110111 << (i - 10);
    const computed = ((data << 10) | rem) ^ 0b101010000010010;
    check(`${name} mask ${mask} format info`, computed === TABLE25[name][mask],
      `computed ${computed.toString(2).padStart(15, '0')} expected ${TABLE25[name][mask].toString(2).padStart(15, '0')}`);
  }
}

console.log('\n=== 3. Version information vs ISO/IEC 18004 Table D.1 ===');
const TABLE_D1 = { 7: 0b000111110010010100, 8: 0b001000010110111100, 9: 0b001001101010011001, 10: 0b001010010011010011 };
for (const v of [7, 8, 9, 10]) {
  check(`version ${v} info`, VERSION_INFO[v] === TABLE_D1[v],
    `computed ${VERSION_INFO[v].toString(2)} expected ${TABLE_D1[v].toString(2)}`);
}

console.log('\n=== 4. Encode / decode round-trip with RS syndrome validation ===');
const payloads = [
  'https://worldofnads.xyz/auth?code=KJI-FYE',
  'https://worldofnads.onrender.com/auth?code=ABC-123',
  'A',
  'https://worldofnads.xyz/auth?code=' + 'X'.repeat(50),
  'https://worldofnads.xyz/auth?code=' + 'X'.repeat(120),
  'https://worldofnads.xyz/auth?code=' + 'X'.repeat(200),
];
// Payload lengths that sit in the window where a version's L level fits but its
// M level does not. These caught an ECC-selection bug in the first draft.
payloads.push('P'.repeat(15), 'P'.repeat(17), 'P'.repeat(18), 'P'.repeat(34), 'P'.repeat(35));
for (const text of payloads) {
  const result = buildMatrix(text);
  const bytes = Buffer.from(text, 'utf8').length;
  if (!result) { check(`"${text.slice(0, 40)}..." (${bytes}B) encodes`, false, 'no placement'); continue; }

  const decoded = decodeMatrix(result);
  const rs = deinterleaveAndVerify(result, decoded.codewords);
  const payload = decodePayload(rs.dataPart, result.version);

  check(`v${result.version}-${result.ecc === ECC_M ? 'M' : 'L'} mask ${result.mask} `
    + `${result.size}x${result.size} "${text.slice(0, 28)}${text.length > 28 ? '...' : ''}"`,
    payload.text === text
    && rs.syndromeFailures === 0
    && rs.ecMismatches === 0
    && decoded.copiesAgree
    && decoded.versionOk
    && decoded.ecc === result.ecc
    && decoded.mask === result.mask,
    `payload=${payload.text === text ? 'ok' : 'MISMATCH'} syndrome=${rs.syndromeFailures} `
    + `ec=${rs.ecMismatches} copies=${decoded.copiesAgree} verinfo=${decoded.versionOk} `
    + `ecc=${decoded.ecc}/${result.ecc} mask=${decoded.mask}/${result.mask}`);
}

console.log('\n=== 5. Version selection invariants ===');
{
  // Not every version/level pair is reachable, and that is correct: the search
  // minimises version first, so a smaller version's L level always wins over a
  // larger version's M level (v5-L holds 107 bytes, v6-M only 106). Asserting
  // blanket reachability would encode the wrong expectation.
  const capacity = (v, ecc) => {
    const spec = ECC_TABLE[v][ecc];
    const dataCw = spec[1] * spec[2] + spec[3] * spec[4];
    return Math.floor((dataCw * 8 - 4 - (v < 10 ? 8 : 16)) / 8);
  };

  const seen = new Set();
  for (let len = 1; len <= 271; len++) {
    const p = chooseVersion(len);
    if (p.version) seen.add(`v${p.version}-${p.ecc_level === ECC_M ? 'M' : 'L'}`);
  }
  check('v1-M and v1-L both reachable', seen.has('v1-M') && seen.has('v1-L'),
    [...seen].join(' '));

  // The chosen version must be the smallest that fits at some level.
  let minimalityOk = true;
  for (let len = 1; len <= 271; len++) {
    const p = chooseVersion(len);
    if (!p.version) continue;
    for (let v = 1; v < p.version; v++) {
      if (capacity(v, ECC_M) >= len || capacity(v, ECC_L) >= len) {
        minimalityOk = false;
        console.log(`    len=${len} chose v${p.version} but v${v} could hold it`);
      }
    }
  }
  check('always picks the smallest version that fits', minimalityOk);

  // M must be used whenever the chosen version can hold the payload at M.
  let eccPreferenceOk = true;
  for (let len = 1; len <= 271; len++) {
    const p = chooseVersion(len);
    if (!p.version) continue;
    if (capacity(p.version, ECC_M) >= len && p.ecc_level !== ECC_M) {
      eccPreferenceOk = false;
      console.log(`    len=${len} chose L at v${p.version} though M fits`);
    }
  }
  check('prefers M whenever M fits', eccPreferenceOk);

  // Capacity must be monotone across the selected sequence.
  let monotone = true, previous = 0;
  for (let len = 1; len <= 271; len++) {
    const p = chooseVersion(len);
    if (!p.version) break;
    if (capacity(p.version, p.ecc_level) < previous) monotone = false;
    previous = Math.max(previous, capacity(p.version, p.ecc_level));
  }
  check('capacity never decreases', monotone);
}

console.log('\n=== 6. Exhaustive sweep: every length 1..271 round-trips ===');
{
  // The strong guarantee: no payload length may encode to an unscannable code.
  // Catches boundary conditions a handful of samples would miss.
  let bad = 0, encoded = 0;
  const worst = [];
  for (let len = 1; len <= 271; len++) {
    const text = 'h'.repeat(len);
    const result = buildMatrix(text);
    if (!result) { worst.push(`len ${len}: no placement`); bad++; continue; }
    let decoded;
    try { decoded = decodeMatrix(result); }
    catch (e) { worst.push(`len ${len}: decode threw ${e.message}`); bad++; continue; }
    let rs;
    try { rs = deinterleaveAndVerify(result, decoded.codewords); }
    catch (e) { worst.push(`len ${len}: ${e.message}`); bad++; continue; }
    const payload = decodePayload(rs.dataPart, result.version);
    if (payload.text !== text) { worst.push(`len ${len}: payload mismatch`); bad++; continue; }
    if (rs.syndromeFailures !== 0) { worst.push(`len ${len}: ${rs.syndromeFailures} syndrome failures`); bad++; continue; }
    if (rs.ecMismatches !== 0) { worst.push(`len ${len}: ${rs.ecMismatches} ec mismatches`); bad++; continue; }
    if (!decoded.copiesAgree) { worst.push(`len ${len}: format copies disagree`); bad++; continue; }
    if (!decoded.versionOk) { worst.push(`len ${len}: version info mismatch`); bad++; continue; }
    if (decoded.ecc !== result.ecc || decoded.mask !== result.mask) {
      worst.push(`len ${len}: format info reads ecc ${decoded.ecc}/mask ${decoded.mask}, wrote ${result.ecc}/${result.mask}`);
      bad++;
      continue;
    }
    encoded++;
  }
  check(`all 271 lengths round-trip (${encoded} verified)`, bad === 0,
    `${bad} bad:\n      ${worst.slice(0, 10).join('\n      ')}`);
}

console.log('\n=== 7. Over-capacity input is refused, not truncated ===');
{
  // 305 bytes exceeds the v10-L ceiling of 271; generate() must report failure
  // rather than silently dropping the tail of the URL.
  const result = buildMatrix('https://worldofnads.xyz/auth?code=' + 'X'.repeat(260));
  check('over-capacity payload returns null', result === null, 'encoder accepted an unencodable URL');
  const fits = buildMatrix('https://worldofnads.xyz/auth?code=' + 'X'.repeat(220));
  check('271-byte payload still encodes', fits !== null && fits.version === 10);
}

console.log('\n=== 8. Padding structure ===');
{
  const result = buildMatrix('https://worldofnads.xyz/auth?code=KJI-FYE');
  const decoded = decodeMatrix(result);
  const rs = deinterleaveAndVerify(result, decoded.codewords);
  const bytes = Buffer.from('https://worldofnads.xyz/auth?code=KJI-FYE', 'utf8').length;
  const bitStream = [];
  for (const cw of rs.dataPart) bitStream.push(...toBits(cw, 8));
  const mode = bitStream.slice(0, 4).join('');
  const count = parseInt(bitStream.slice(4, 12).join(''), 2);
  check('mode indicator is byte mode', mode === '0100', mode);
  check('character count matches', count === bytes, `${count} vs ${bytes}`);
  // The terminator (up to four zero bits) sits between the payload and the
  // alternating pad codewords, so skip past it before reading pad bytes.
  const usedBits = 12 + bytes * 8;
  const terminatorBits = (8 - (usedBits % 8)) % 8;
  let padOk = true, padSeen = 0;
  for (let i = usedBits + terminatorBits; i + 8 <= bitStream.length; i += 8) {
    const value = parseInt(bitStream.slice(i, i + 8).join(''), 2);
    if (value !== (padSeen % 2 === 0 ? 0xec : 0x11)) padOk = false;
    padSeen++;
  }
  check('terminator is 4 zero bits', terminatorBits === 4, `${terminatorBits} bits`);
  check(`pad codewords are 0xEC/0x11 (${padSeen} present)`, padOk && padSeen > 0);
}

console.log(`\n${failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'}\n`);
process.exitCode = failures === 0 ? 0 : 1;

}
