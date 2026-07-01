const fs = require('fs');

const scenePath = 'godot/scenes/maps/salmograd.tscn';
let content = fs.readFileSync(scenePath, 'utf-8');

// 1. Set aggressive LOD bias for all MeshInstance3D nodes
// Looking for lines like 'lod_bias = ...' or adding them to node blocks
const lines = content.split(/\r?\n/);
const newLines = [];
let inTargetNode = false;

for (let i = 0; i < lines.length; i++) {
    let line = lines[i];

    // Identify small props or objects that don't need high detail
    if (line.startsWith('[node') && (line.includes('Package') || line.includes('Object_') || line.includes('Sketchfab_Scene'))) {
        inTargetNode = true;
    }

    if (inTargetNode) {
        if (line.trim() === '' || line.startsWith('[')) {
            inTargetNode = false;
        } else {
            // Disable shadows and force low LOD
            if (line.includes('lod_bias')) {
                line = line.replace(/lod_bias = [0-9.]+/, 'lod_bias = 0.1');
            }
            if (!line.includes('cast_shadow') && line.includes('transform')) {
                // Add cast_shadow = 0 (Off) to the node
                newLines.push('cast_shadow = 0');
            }
        }
    }
    
    // Global fix for nested GLB internals that are currently drawing even if hidden
    if (line.includes('unique_id=616750535') || line.includes('unique_id=1056977064')) {
         // These are the container internals I found earlier
         line += '\nvisible = false';
    }

    newLines.push(line);
}

fs.writeFileSync(scenePath, newLines.join('\n'));
console.log("Salmograd performance safeguards applied: Shadows disabled for props, LODs aggressive.");
