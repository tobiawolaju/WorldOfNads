const fs = require('fs');

const scenePath = 'godot/scenes/maps/salmograd.tscn';
const outputPath = 'godot/scenes/maps/salmograd_optimized.tscn';

// IDs from salmograd.tscn and package.tscn
// Package PackedScene ID in salmograd.tscn is 13_hl6kx
const PACKAGE_EXT_ID = '13_hl6kx';

function parseTransform(line) {
    const match = line.match(/transform = Transform3D\(([^)]+)\)/);
    if (!match) return null;
    return match[1];
}

let content = fs.readFileSync(scenePath, 'utf-8');
const lines = content.split(/\r?\n/);
const newLines = [];

const packageTransforms = [];
let inPackageNode = false;

for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    if (line.startsWith('[node') && line.includes(`instance=ExtResource("${PACKAGE_EXT_ID}")`)) {
        inPackageNode = true;
        // Look ahead for transform
        let foundTransform = false;
        for(let j=i+1; j<i+5 && j<lines.length; j++) {
            if (lines[j].includes('transform = Transform3D')) {
                packageTransforms.push(parseTransform(lines[j]));
                foundTransform = true;
                break;
            }
        }
        if (!foundTransform) {
            packageTransforms.push("1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0"); // Identity if missing
        }
        continue;
    }

    if (inPackageNode) {
        if (line.trim() === '' || line.startsWith('[')) {
            inPackageNode = false;
            // fall through to process this line
        } else {
            continue; 
        }
    }

    newLines.push(line);
}

console.log(`Found ${packageTransforms.length} packages to optimize.`);

// Add MultiMesh resources and node at the end (simplified for demo)
// In a real scenario, we'd need to define the MultiMesh resource properly with the PackedFloat32Array of transforms.
// Since generating the binary PackedFloat32Array for transforms is complex in a text script, 
// I will propose a "Group Merge" approach or provide instructions for the Godot Editor.

// HOWEVER, I can do a "Node-Level" optimization: 
// Disable shadows or simplify collision for all these packages via script.

fs.writeFileSync('optimization_report.txt', `Found ${packageTransforms.length} Package instances.\nTransforms extracted.`);
console.log("Optimization data extracted to optimization_report.txt");
