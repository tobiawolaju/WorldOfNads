const { PNG } = require('pngjs');
const fs = require('fs');
const path = require('path');

// Textures to pack into the atlas
const entries = [
  { id: 'cover',     file: 'godot/newport/assets/images/cover.png',         w: 400,  h: 82   },
  { id: 'white_circle1', file: 'godot/newport/assets/images/white_circle1.png', w: 500, h: 500 },
];

// Read all PNGs
const images = entries.map(e => {
  const data = fs.readFileSync(e.file);
  const png = PNG.sync.read(data);
  return { ...e, png };
});

// Layout: pack them in rows (simple strip layout)
const padding = 1;
let atlasW = 0;
let atlasH = 0;
let yOffset = 0;

const layout = images.map((img, i) => {
  const x = 0;
  const y = yOffset;
  yOffset += img.h + padding;
  atlasW = Math.max(atlasW, img.w);
  atlasH = yOffset;
  return { ...img, x, y };
});

// Round up to power of 2 for GPU
atlasW = 1;
while (atlasW < 512) atlasW *= 2;
atlasH = 1;
while (atlasH < (yOffset)) atlasH *= 2;

console.log(`Atlas size: ${atlasW}x${atlasH}`);
console.log('Layout:');
layout.forEach(l => console.log(`  ${l.id}: (${l.x}, ${l.y}) ${l.w}x${l.h}`));

// Create atlas image
const atlas = new PNG({ width: atlasW, height: atlasH, fill: true });
// fill with transparent black
for (let i = 0; i < atlas.data.length; i++) {
  atlas.data[i] = 0;
}

layout.forEach(({ png, x, y }) => {
  PNG.bitblt(png, atlas, 0, 0, png.width, png.height, x, y);
});

// Write atlas
const atlasPath = 'godot/newport/assets/images/ui_atlas.png';
fs.writeFileSync(atlasPath, PNG.sync.write(atlas));
console.log(`Wrote ${atlasPath}`);

// Write layout metadata
const outDir = 'tools';
const meta = layout.map(l => ({
  id: l.id,
  x: l.x, y: l.y,
  w: l.w, h: l.h,
  file: l.file.replace(/\\/g, '/').replace('godot/', 'res://'),
}));
fs.writeFileSync('tools/atlas_ui_meta.json', JSON.stringify(meta, null, 2));
console.log('Wrote tools/atlas_ui_meta.json');

// Output the regions in .tscn format
console.log('\nAdd these AtlasTexture sub-resources to your .tscn files:');
meta.forEach(m => {
  console.log(`
[sub_resource type="AtlasTexture" id="AtlasTexture_${m.id}"]
atlas = ExtResource("ui_atlas")
region = Rect2(${m.x}, ${m.y}, ${m.w}, ${m.h})`);
});
