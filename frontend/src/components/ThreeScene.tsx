import React, { Suspense, useEffect, useMemo, useRef, useState } from "react";
import { Canvas, useFrame, useLoader } from "@react-three/fiber";
import { OrbitControls, useFBX, Environment, Lightformer } from "@react-three/drei";
import { FBXLoader } from "three/examples/jsm/loaders/FBXLoader.js";
import { OBJLoader } from "three/examples/jsm/loaders/OBJLoader.js";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import * as SkeletonUtils from "three/examples/jsm/utils/SkeletonUtils.js";
import * as THREE from "three";
import { resolveShaderType } from "../lib/skinMapping";

// --- Prop Types ---
interface Palette {
  body?: string;
  body_alt?: string;
  cheek?: string;
  eye?: string;
  skin?: string;
}

interface AttachmentConfig {
  shape?: "box" | "cone" | "sphere" | "cylinder" | "torus";
  color?: string;
}

interface SkinConfig {
  palette?: Palette;
  outline_color?: string;
  crown_color?: string;
  face_texture?: string;
  shader?: "ghost" | "gold" | "shadow" | "angel" | "default" | "void" | "unshaded";
  shaderTargets?: ("body" | "cheek" | "eye" | "attachment")[];
  attachment?: AttachmentConfig;
  /**
   * Names of the attachments this skin wears, e.g. ["duck", "hair_001"].
   * Each name is a node in godot/scenes/skin.tscn exported to
   * /attachments/<name>.glb by godot/tools/export_attachments.gd. Unknown
   * names are skipped, so new attachments never break old skins.
   */
  attachments?: string[];
  // Legacy/direct fields for backward compat
  color?: string;
  cheekColor?: string;
  attachmentColor?: string;
  attachmentShape?: "box" | "cone" | "sphere" | "cylinder" | "torus";
  eyeColor?: string;
  rawFragmentShader?: string;
  rawVertexShader?: string;
}

interface StoreItem {
  id: string;
  name: string;
  skinConfig?: SkinConfig;
}

interface ThreeSceneProps {
  equippedSkin?: StoreItem | null;
  isStoreOpen?: boolean;
}

// --- Shader Definition for Water Bubble Effect ---
const vertexShader = `
  varying vec3 vNormal;
  varying vec3 vViewPosition;
  void main() {
    vec4 modelViewPosition = modelViewMatrix * vec4(position, 1.0);
    vViewPosition = -modelViewPosition.xyz;
    vNormal = normalize(normalMatrix * normal);
    gl_Position = projectionMatrix * modelViewPosition;
  }
`;

const fragmentShader = `
  precision mediump float;
  uniform float uTime;
  varying vec3 vNormal;
  varying vec3 vViewPosition;
  void main() {
    vec3 viewDir = normalize(vViewPosition);
    float fresnel = 1.0 - dot(viewDir, vNormal);
    fresnel = pow(fresnel, 2.5);

    vec3 color;
    color.r = sin(fresnel * 5.0 - uTime * 0.5) * 0.5 + 0.5;
    color.g = sin(fresnel * 5.0 - uTime * 0.5 + 2.094) * 0.5 + 0.5;
    color.b = sin(fresnel * 5.0 - uTime * 0.5 + 4.188) * 0.5 + 0.5;

    gl_FragColor = vec4(color, fresnel * 0.8);
  }
`;

// --- Chicken Component with Shader ---
interface ChickenProps {
  position: [number, number, number];
  rotation: [number, number, number];
  scale?: number;
}
const Chicken: React.FC<ChickenProps> = ({
  position,
  rotation,
  scale = 6,
}) => {
  const obj = useLoader(OBJLoader, "/Chicken.obj");
  const model = useMemo(() => obj.clone(), [obj]);
  const shaderRef = useRef<THREE.ShaderMaterial>(null);

  useFrame(({ clock }) => {
    if (shaderRef.current) {
      shaderRef.current.uniforms.uTime.value = clock.getElapsedTime();
    }
  });

  useEffect(() => {
    const bubbleMaterial = new THREE.ShaderMaterial({
      uniforms: { uTime: { value: 0 } },
      vertexShader,
      fragmentShader,
      transparent: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    })
    shaderRef.current = bubbleMaterial;
    model.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        child.material = bubbleMaterial;
      }
    });
    // Cleanup
    return () => {
      bubbleMaterial.dispose();
      // Note: We DO NOT dispose of child.geometry or child.material here
      // because they are shared assets from the FBX loader cache.
    };
  }, [model]);

  return (
    <primitive
      object={model}
      position={position}
      rotation={rotation}
      scale={scale}
    />
  );
};

// --- Named attachment loading (duck, hair, hats, ...) ---
// skinConfig.attachments lists nodes taken from godot/scenes/skin.tscn and
// exported to /attachments/*.glb by godot/tools/export_attachments.gd. The GLB
// already carries the node's authored bone-local transform, so parenting it
// under the matching bone reproduces the game's placement. Everything is cached
// and failures are non-fatal: a missing manifest or file just means the preview
// dresses nothing, which keeps unknown/future attachments safe.
type AttachmentManifestEntry = { file: string; bone: string };
type AttachmentManifest = Record<string, AttachmentManifestEntry>;

const ATTACHMENTS_DIR = "/attachments";
let attachmentManifestPromise: Promise<AttachmentManifest | null> | null = null;
const attachmentFileCache = new Map<string, Promise<THREE.Group | null>>();

function loadAttachmentManifest(): Promise<AttachmentManifest | null> {
  if (!attachmentManifestPromise) {
    attachmentManifestPromise = fetch(`${ATTACHMENTS_DIR}/manifest.json`)
      .then((res) => (res.ok ? (res.json() as Promise<AttachmentManifest>) : null))
      .catch(() => null);
  }
  return attachmentManifestPromise;
}

function loadAttachment(file: string): Promise<THREE.Group | null> {
  let pending = attachmentFileCache.get(file);
  if (!pending) {
    pending = new GLTFLoader()
      .loadAsync(`${ATTACHMENTS_DIR}/${file}`)
      .then((gltf) => gltf.scene as THREE.Group)
      .catch((err) => {
        console.warn(`[ThreeScene] attachment "${file}" failed to load`, err);
        return null;
      });
    attachmentFileCache.set(file, pending);
  }
  return pending;
}

// Godot sanitises Mixamo bone names ("mixamorig:Head" -> "mixamorig_Head") while
// three.js strips the separators entirely ("mixamorigHead"), so compare on a
// normalised form that ignores case and any punctuation.
function normalizeBoneName(name: string): string {
  return String(name).toLowerCase().replace(/[^a-z0-9]/g, "");
}

function findBone(model: THREE.Object3D, boneName: string): THREE.Object3D | null {
  const exact = model.getObjectByName(boneName);
  if (exact) return exact;
  const needle = normalizeBoneName(boneName);
  if (!needle) return null;
  let loose: THREE.Object3D | null = null;
  let match: THREE.Object3D | null = null;
  model.traverse((child) => {
    if (match) return;
    const current = normalizeBoneName(child.name);
    if (!current) return;
    if (current === needle) match = child;
    else if (!loose && current.includes(needle)) loose = child;
  });
  return match || loose;
}

// --- Mouth base part (shipped inside nad.fbx) ---
//
// Earlier attempts loaded a standalone mouth (mouth.glb / nad2.glb) and tried
// to attach/bake it onto the face. The FBX export of the mouth's raw vertices
// sits in bind/skeleton space near the hips, and the runtime bake into
// head-bone-local coordinates put the mesh in entirely the wrong place at a
// huge scale. The user then added the mouth mesh directly into nad.fbx in the
// right position on the face. Because the model below is
// `SkeletonUtils.clone(fbx)`, the mouth rides along with the body, skinned to
// the same Mixamo skeleton, so it animates with the head for free. The colour
// effect below finds the "mouth" mesh and swaps in the procedural mouth
// shader (the palette tints flow through the same palette as the body/cheek).
//

// Port of godot/assets/shaders/eye.gdshader: an unshaded sphere with a single
// dot that always faces the camera. Everything is measured in view space (the
// camera sits at the origin), so the dot does not depend on where the mesh was
// authored. It rides on a MeshBasicMaterial through onBeforeCompile so the
// built-in normal + skinning pipeline is kept (the nad's eyes are
// SkinnedMeshes) and tone mapping / colour space still run exactly like on
// every other material - the only thing replaced is the final colour.
//
// The uniform values mirror the ShaderMaterial on eye_L/eye_R in
// godot/scenes/skin.tscn; eye_color is the one per-skin tint, pushed the same
// way SkinApplier._tint_eye does it. dot_roll and debug_flat are not ported:
// roll only matters for an elongated dot (there is none, and every shift is
// 0), debug_flat only paints magenta.
function createEyeMaterial(eyeColor: THREE.Color): THREE.MeshBasicMaterial {
  const mat = new THREE.MeshBasicMaterial({
    color: 0xffffff,
    side: THREE.DoubleSide, // Godot: render_mode cull_disabled
  });
  mat.onBeforeCompile = (shader) => {
    if (
      !shader.vertexShader.includes("#include <project_vertex>") ||
      !shader.fragmentShader.includes("#include <opaque_fragment>")
    ) {
      console.warn("[ThreeScene] eye shader injection point missing - three.js upgrade?");
      return;
    }
    Object.assign(shader.uniforms, {
      eye_color: { value: eyeColor.clone() },
      // skin.tscn authors the pupil teal; three stores colours linear.
      pupil_color: { value: new THREE.Color().setRGB(0.0, 0.50997, 0.534838, THREE.SRGBColorSpace) },
      pupil_size: { value: 0.468 },
      pupil_softness: { value: 0.3 },
      rim_darken: { value: 0.0 },
      dot_shift_x: { value: 0.0 },
      dot_shift_y: { value: 0.0 },
      // skin.tscn's eye sphere carries inward normals, so it flips (1.0). The
      // nad.fbx eye spheres are outward-facing (probed: radialDot ~ +0.96),
      // so no flip here - either way the dot lands on the camera-facing side.
      flip_dot: { value: 0.0 },
    });
    shader.vertexShader = shader.vertexShader
      .replace(
        "#include <common>",
        `#include <common>
varying vec3 vEyeViewNormal;
varying vec3 vEyeViewPosition;`
      )
      .replace(
        "#include <project_vertex>",
        `#include <project_vertex>
  vEyeViewPosition = mvPosition.xyz;
  vEyeViewNormal = transformedNormal;`
      );
    shader.fragmentShader = shader.fragmentShader
      .replace(
        "#include <common>",
        `#include <common>
varying vec3 vEyeViewNormal;
varying vec3 vEyeViewPosition;
uniform vec3 eye_color;
uniform vec3 pupil_color;
uniform float pupil_size;
uniform float pupil_softness;
uniform float rim_darken;
uniform float dot_shift_x;
uniform float dot_shift_y;
uniform float flip_dot;`
      )
      .replace(
        "#include <opaque_fragment>",
        `#include <opaque_fragment>
  vec3 to_camera = normalize(-vEyeViewPosition);
  vec3 surface_normal = normalize(vEyeViewNormal) * mix(1.0, -1.0, flip_dot);
  vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_camera) + vec3(0.0001, 0.0, 0.0));
  vec3 up = normalize(cross(to_camera, right));
  vec3 aim = normalize(to_camera + right * dot_shift_x + up * dot_shift_y);
  float facing = acos(clamp(dot(surface_normal, aim), -1.0, 1.0));
  float softness = max(pupil_softness, 0.001);
  float inside = 1.0 - smoothstep(pupil_size - softness, pupil_size + softness, facing);
  float rim = smoothstep(0.9, 1.5708, acos(clamp(dot(surface_normal, to_camera), -1.0, 1.0)));
  vec3 eyeShade = mix(eye_color, eye_color * (1.0 - rim_darken), rim);
  eyeShade = mix(eyeShade, pupil_color, inside);
  gl_FragColor = vec4(eyeShade, diffuseColor.a);`
      );
  };
  return mat;
}



// Port of godot/assets/shaders/mouth_wobble.gdshader — procedural mouth with
// lips, parallax cavity, and two bunny teeth. Applied via onBeforeCompile on a
// MeshBasicMaterial (same pattern as the eyes).
//
// nad.fbx bakes the mouth's Blender UVs as garbage values outside 0..1 (u=0,
// v≈1.6-1.8), so the shader cannot read attribute `uv`. Instead the vertex
// shader synthesises a UV by mapping the mouth's object-space XY bounding box
// (bounds) into 0..1 — the mouth plate sits in the XY plane of its local
// frame, and the whole mesh is SkinnedMesh, so `transformed` tracks the plate
// even while it follows the head bone. Same illusion as authored UVs, no
// position/scale changes.
//
// V-convention: the original mouth mesh (nad2.glb textura / Godot) has v=0 at
// the TOP of the plate and v increasing downward, so the synthetic V is
// inverted (1 - normalized) to match. That keeps the teeth hanging from the
// upper lip in the same orientation Godot rendered.
//
// The uniform defaults mirror the ShaderMaterial on Skeleton3D/mouth in
// godot/scenes/skin.tscn. mouth_color / lip_outline_color are the per-skin
// tints (pushed like the palette tint on the body).
function createMouthMaterial(
  palette: { mouth?: string; lipOutline?: string; tooth?: string },
  bounds?: { min: [number, number]; size: [number, number] }
): THREE.MeshBasicMaterial {
  const mat = new THREE.MeshBasicMaterial({
    color: 0xffffff,
    transparent: true,
    depthWrite: true,
    side: THREE.DoubleSide, // Godot: render_mode cull_disabled
  });

  const uniforms = {
    // Colors (sRGB → linear handled by three)
    mouthColor: { value: new THREE.Color(palette.mouth || "#ff2b00") },
    lipOutlineColor: { value: new THREE.Color(palette.lipOutline || "#ff7d00") },
    toothColor: { value: new THREE.Color(palette.tooth || "#ffffff") },
    // Lip params (skin.tscn ShaderMaterial_lr00t)
    lipOutlineThickness: { value: 0.188 },
    // Tooth params
    toothWidth: { value: 0.268 },
    toothHeight: { value: 0.245 },
    toothSpacing: { value: 0.325 },
    toothDrop: { value: -0.605 },
    toothRoundness: { value: 0.01 },
    // Mouth size
    width: { value: 0.36 },
    height: { value: 0.189 },
    // Cavity
    layers: { value: 5 },
    depth: { value: 0.214 },
    taper: { value: 0.65 },
    darkness: { value: 1.0 },
    endX: { value: 0.144 },
    endY: { value: 0.0 },
    // Parallax
    parallaxFactor: { value: 1.0 },
    // Synthetic UV: mouth's object-space XY bbox mapped to 0..1 (see header).
    mouthBoundsMin: { value: new THREE.Vector2(bounds?.min[0] ?? 0, bounds?.min[1] ?? 0) },
    mouthBoundsSize: { value: new THREE.Vector2(Math.max(bounds?.size[0] ?? 1, 1e-6), Math.max(bounds?.size[1] ?? 1, 1e-6)) },
    // Shift the drawn mouth down within the plate. The mouth sits at UV
    // (0.5, 0.5) = the plate centre; adding to the (downward-incrementing) V
    // relocates the whole mouth (lips, cavity, teeth) downward without
    // touching the mesh. Currently 0 (mouth centred on the plate like the
    // Godot render) — bump if a nudge is wanted after verifying orientation.
    mouthShiftY: { value: 0.0 },
  };

  mat.onBeforeCompile = (shader) => {
    if (
      !shader.vertexShader.includes("#include <project_vertex>") ||
      !shader.fragmentShader.includes("#include <opaque_fragment>")
    ) {
      console.warn("[ThreeScene] mouth shader injection point missing - three.js upgrade?");
      return;
    }

    // Inject uniforms
    Object.assign(shader.uniforms, uniforms);

    // Inject varyings + uniforms; build the mouth UV from the skinned
    // object-space position (the mouth plate's XY plane) instead of the
    // garbage `uv` attribute coming out of the Blender FBX export.
    shader.vertexShader = shader.vertexShader
      .replace(
        "#include <common>",
        `#include <common>
varying vec2 vMouthUv;
varying vec3 vMouthViewPos;
uniform vec2 mouthBoundsMin;
uniform vec2 mouthBoundsSize;
uniform float mouthShiftY;`
      )
      .replace(
        "#include <project_vertex>",
        `#include <project_vertex>
  // Synthesise the mouth UV from the skinned object-space position. V is
  // inverted (v=0 at the top) to match the original mesh's UV convention.
  vMouthUv = vec2(
    (transformed.x - mouthBoundsMin.x) / mouthBoundsSize.x,
    1.0 - (transformed.y - mouthBoundsMin.y) / mouthBoundsSize.y
  ) + vec2(0.0, mouthShiftY);
  vMouthViewPos = mvPosition.xyz;`
      );

    // Replace fragment shader with mouth_wobble logic
    shader.fragmentShader = shader.fragmentShader
      .replace(
        "#include <common>",
        `#include <common>
varying vec2 vMouthUv;
varying vec3 vMouthViewPos;
uniform vec3 mouthColor;
uniform vec3 lipOutlineColor;
uniform vec3 toothColor;
uniform float lipOutlineThickness;
uniform float toothWidth;
uniform float toothHeight;
uniform float toothSpacing;
uniform float toothDrop;
uniform float toothRoundness;
uniform float width;
uniform float height;
uniform int layers;
uniform float depth;
uniform float taper;
uniform float darkness;
uniform float endX;
uniform float endY;
uniform float parallaxFactor;

float roundedBox(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}`
      )
      .replace(
        "#include <opaque_fragment>",
        `#include <opaque_fragment>
  vec2 baseUv = vMouthUv;

  vec2 baseP = baseUv * 2.0 - 1.0;
  baseP.x /= width;
  baseP.y /= height;

  float baseShape = baseP.x * baseP.x + baseP.y * baseP.y;

  // Mouth opening
  float opening = step(baseShape, 1.0);

  // Lip outline
  float innerRadius = 1.0 - lipOutlineThickness;
  float innerShape =
    (baseP.x / innerRadius) * (baseP.x / innerRadius) +
    (baseP.y / innerRadius) * (baseP.y / innerRadius);
  float innerOpening = step(innerShape, 1.0);
  float lipOutline = opening - innerOpening;

  // View / parallax basis. Godot uses the mesh TANGENT/NORMAL attributes; this
  // synthesises an equivalent camera-relative basis from the view-space normal
  // (same trick as the eye shader), so the parallax follows the orbit camera.
  vec3 toCamera = normalize(-vMouthViewPos);
  vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), toCamera) + vec3(0.0001, 0.0, 0.0));
  vec3 up = normalize(cross(toCamera, right));
  vec2 viewOffset = vec2(dot(toCamera, right), dot(toCamera, up));

  // Cavity (ray-marched layers, capped at 32 for GLSL loop unrolling)
  float deepest = 0.0;
  float deepestT = 0.0;

  for (int i = 0; i < 32; i++) {
    if (i >= layers) break;
    float t = float(i) / float(max(layers - 1, 1));
    float z = t * depth;

    vec2 uv = baseUv;
    uv -= viewOffset * z * parallaxFactor;
    uv -= vec2(endX, endY) * t;

    float scale = mix(1.0, taper, t);

    vec2 p = uv * 2.0 - 1.0;
    p.x /= width * scale;
    p.y /= height * scale;

    float shape = p.x * p.x + p.y * p.y;
    float layerMask = step(shape, 1.0);

    if (layerMask > 0.0) {
      deepest = 1.0;
      deepestT = t;
    }
  }

  // Cavity color
  float darkAmount = deepestT * darkness;
  vec3 cavityColor = mix(mouthColor, vec3(0.0), darkAmount);

  // Start with cavity
  vec3 finalColor = mix(cavityColor, lipOutlineColor, lipOutline);

  // Two bunny teeth
  float toothMask = 0.0;

  // Left tooth
  vec2 leftTooth = baseP - vec2(-toothSpacing, toothDrop);
  float leftShape = roundedBox(leftTooth, vec2(toothWidth, toothHeight), toothRoundness);
  float leftMask = step(leftShape, 0.0);

  // Right tooth
  vec2 rightTooth = baseP - vec2(toothSpacing, toothDrop);
  float rightShape = roundedBox(rightTooth, vec2(toothWidth, toothHeight), toothRoundness);
  float rightMask = step(rightShape, 0.0);

  toothMask = max(leftMask, rightMask);
  toothMask *= opening;

  // Teeth go over the cavity (behind the lips)
  finalColor = mix(cavityColor, toothColor, toothMask);

  // Lip outline is ALWAYS on top
  finalColor = mix(finalColor, lipOutlineColor, lipOutline);

  float alpha = max(opening, toothMask);
  gl_FragColor = vec4(finalColor, alpha);`
      );

    mat.userData.shader = shader;
  };

  return mat;
}

// --- Animated Nad Model Component ---
interface NadModelProps {
  position?: [number, number, number];
  rotation?: [number, number, number];
  scale?: number;
  equippedSkin?: StoreItem | null;
}
const NadModel: React.FC<NadModelProps> = ({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  equippedSkin,
}) => {
  const fbx = useFBX("/nad.fbx");
  const model = useMemo(() => SkeletonUtils.clone(fbx), [fbx]);
  const mixer = useMemo(() => new THREE.AnimationMixer(model), [model]);
  const animatedMaterialsRef = useRef<THREE.Material[]>([]);
  const outlineMeshesRef = useRef<THREE.Mesh[]>([]);

  function createToonGradientTexture(steps: number = 4): THREE.CanvasTexture {
    const canvas = document.createElement('canvas');
    canvas.width = 64;
    canvas.height = 8;
    const ctx = canvas.getContext('2d')!;
    // three.js samples the gradient map with coord = vec2(dotNL * 0.5 + 0.5, 0.0),
    // i.e. along X only. A ramp drawn vertically would be read as one constant
    // column and every sample would come back identical, which makes the "shaded"
    // edition render completely flat - so the ramp has to run horizontally.
    const gradient = ctx.createLinearGradient(0, 0, 64, 0);
    for (let i = 0; i < steps; i++) {
      const t = i / (steps - 1);
      const val = Math.floor(t * 255);
      gradient.addColorStop(t, `rgb(${val},${val},${val})`);
    }
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, 64, 8);
    const texture = new THREE.CanvasTexture(canvas);
    texture.minFilter = THREE.NearestFilter;
    texture.magFilter = THREE.NearestFilter;
    texture.generateMipmaps = false;
    return texture;
  }

  function disposeOutlineMeshes() {
    outlineMeshesRef.current.forEach(m => {
      m.parent?.remove(m);
      m.geometry.dispose();
      if (Array.isArray(m.material)) {
        m.material.forEach(mat => mat.dispose());
      } else {
        m.material.dispose();
      }
    });
    outlineMeshesRef.current = [];
  }

  useEffect(() => {
    animatedMaterialsRef.current = [];
    const box = new THREE.Box3().setFromObject(model);
    const size = new THREE.Vector3();
    box.getSize(size);

    const maxDim = Math.max(size.x, size.y, size.z);
    if (maxDim > 0) {
      const s = 1 / maxDim;
      model.scale.setScalar(s);
    }

    const center = new THREE.Vector3();
    box.getCenter(center);
    // Center on X and Z axes, but align bottom (feet) to Y=0
    model.position.x = -center.x * model.scale.x;
    model.position.z = -center.z * model.scale.z;
    model.position.y = -box.min.y * model.scale.y;
  }, [model]);

  // Handle character color change + cel shader + outline
  useEffect(() => {
    animatedMaterialsRef.current = [];

    const pal = equippedSkin?.skinConfig?.palette || {};
    const baseColorHex = pal.body || equippedSkin?.skinConfig?.color || "#ff2496";
    const baseColor = new THREE.Color(baseColorHex);

    const cheekColorHex = pal.cheek || equippedSkin?.skinConfig?.cheekColor;
    const cheekColor = cheekColorHex
      ? new THREE.Color(cheekColorHex)
      : baseColor.clone().lerp(new THREE.Color("#ffffff"), 0.15);

    const eyeColorHex = pal.eye || equippedSkin?.skinConfig?.eyeColor || "#ffffff";
    const eyeColor = new THREE.Color(eyeColorHex);

    const skinColorHex = pal.skin || "#ffffff";
    const skinColor = new THREE.Color(skinColorHex);

    const toonGradient = createToonGradientTexture(4);

    disposeOutlineMeshes();

    model.traverse((child) => {
      if (child instanceof THREE.Mesh && child.name !== "bone-attachment") {
        // Store original material if not already stored
        if (!child.userData.originalMaterial) {
          child.userData.originalMaterial = child.material;
        }

        const name = child.name;
        const isHeadOrBody = /^(body_|Cube$|Cube[._]?00[123]$)/.test(name);
        const isCheek = /^(cheek_|Cube[._]?00[45]$)/.test(name);
        const isEye = /^(eye_|Cube[._]?00[67]$)/.test(name);
        // The mouth ships inside nad.fbx as a SkinnedMesh on the face; it is
        // always re-shaded below (never claimed by apply_skin, like the eyes).
        const isMouth = name === "mouth";

        // Odd numeric skin ids are the shaded edition, even ids the flat
        // variant of the same skin (mirrors SkinApplier in Godot).
        const shaderType = resolveShaderType(equippedSkin?.id, equippedSkin?.skinConfig?.shader);
        const targets = equippedSkin?.skinConfig?.shaderTargets || ["body", "cheek", "eye", "attachment"];
        const shouldApplyShader = targets.includes(isHeadOrBody ? "body" : isCheek ? "cheek" : isEye ? "eye" : "unknown");

        let newMat: THREE.Material;

        if (isEye) {
          // Eyes keep the camera-facing dot shader in every edition: Godot's
          // apply_skin never claims them (_tint_eye only pushes the palette
          // tint into eye_color), so no shader type replaces them.
          newMat = createEyeMaterial(eyeColor);
        } else if (isMouth) {
          // Apply the Godot mouth_wobble port. The Blender FBX bakes garbage
          // UVs on this mesh (u=0, v out of 0..1), so the shader synthesises
          // its UV from the mouth plate's object-space XY bounding box. Feed
          // that box from the geometry — no position/scale changes.
          const mouthGeo = child.geometry as THREE.BufferGeometry;
          const mouthPos = mouthGeo.getAttribute("position");
          let mMinX = Infinity;
          let mMinY = Infinity;
          let mMaxX = -Infinity;
          let mMaxY = -Infinity;
          for (let i = 0; i < mouthPos.count; i++) {
            const px = mouthPos.getX(i);
            const py = mouthPos.getY(i);
            if (px < mMinX) mMinX = px;
            if (py < mMinY) mMinY = py;
            if (px > mMaxX) mMaxX = px;
            if (py > mMaxY) mMaxY = py;
          }
          newMat = createMouthMaterial(
            {
              mouth: pal.body || "#ff2b05",
              lipOutline: pal.cheek || "#ff7d00",
              tooth: "#fff2d9",
            },
            {
              min: [mMinX, mMinY],
              size: [mMaxX - mMinX, mMaxY - mMinY],
            }
          );
          animatedMaterialsRef.current.push(newMat);
        } else if (shouldApplyShader && shaderType !== "default") {
          if (shaderType === "ghost") {
            newMat = child.userData.originalMaterial.clone();
            newMat.transparent = true;
            newMat.opacity = 0.6;
            newMat.depthWrite = true;
            if ((newMat as any).roughness !== undefined) {
              (newMat as any).roughness = 0.1;
            }
          } else if (shaderType === "gold") {
            const oldColor = (child.userData.originalMaterial as any).color ? (child.userData.originalMaterial as any).color.clone() : new THREE.Color("#ffd700");
            const oldMap = (child.userData.originalMaterial as any).map;
            newMat = new THREE.MeshStandardMaterial({
              color: oldColor,
              map: oldMap,
              metalness: 1.0,
              roughness: 0.1
            });
          } else if (shaderType === "shadow" || shaderType === "void") {
            newMat = new THREE.MeshBasicMaterial({
              depthWrite: shaderType === "void" ? false : true,
              transparent: shaderType === "void" ? true : false,
            });
          } else if (shaderType === "angel") {
            newMat = child.userData.originalMaterial.clone();
            if (isEye && (newMat as any).emissive !== undefined) {
              (newMat as any).emissive = eyeColor.clone();
              (newMat as any).emissiveIntensity = 1.0;
            }
          } else if (shaderType === "unshaded") {
            // Flat skin: no lighting, the colour is the colour. The palette
            // copies below set the exact hue, and outlines still draw - the
            // same combination as Godot's skin_unshaded.gdshader.
            newMat = new THREE.MeshBasicMaterial({ color: 0xffffff });
          } else {
            newMat = child.userData.originalMaterial.clone();
          }
        } else {
          // Default: cel toon shader
          const originalColor = (child.userData.originalMaterial as any).color
            ? (child.userData.originalMaterial as any).color.clone()
            : new THREE.Color("#ffffff");
          newMat = new THREE.MeshToonMaterial({
            color: originalColor,
            gradientMap: toonGradient,
          });
        }

        const rawFrag = equippedSkin?.skinConfig?.rawFragmentShader;
        const rawVert = equippedSkin?.skinConfig?.rawVertexShader;
        // Eyes and the mouth never take the raw overlay either - their own
        // shaders win, the same way SkinApplier gives them nothing but the
        // palette tints.
        if (!isEye && !isMouth && (rawFrag || rawVert)) {
          newMat.onBeforeCompile = (shader) => {
            shader.uniforms.uTime = { value: 0 };
            if (rawFrag) {
              shader.fragmentShader = `uniform float uTime;\n` + shader.fragmentShader.replace(
                '#include <dithering_fragment>',
                `#include <dithering_fragment>\n${rawFrag}`
              );
            }
            if (rawVert) {
              shader.vertexShader = `uniform float uTime;\n` + shader.vertexShader.replace(
                '#include <project_vertex>',
                `#include <project_vertex>\n${rawVert}`
              );
            }
            newMat.userData.shader = shader;
          };
          animatedMaterialsRef.current.push(newMat);
        }

        // Before assigning, dispose the current material IF it's a clone (not the original)
        if (child.material && child.material !== child.userData.originalMaterial) {
          child.material.dispose();
        }

        child.material = newMat;

        // Apply base colors
        if (isHeadOrBody) {
          if ((child.material as any).color) (child.material as any).color.copy(baseColor);
        } else if (isCheek) {
          if ((child.material as any).color) (child.material as any).color.copy(cheekColor);
        } else if (isEye) {
          // Tinted through uniforms inside createEyeMaterial;
          // pushing palette colors elsewhere would miss it.
        }

        // Godot only draws an outline pass for the skins that ask for one: the
        // unshaded edition (black, 1.04) and gold/angel (the skin's own
        // outline_color, 1.04) - see SkinApplier._body_material. The shaded
        // "default" edition, ghost/shadow/void and anything outside
        // shader_targets are drawn plain, with no outline at all. Eyes and the
        // mouth are excluded absolutely: their own shaders have no outline
        // pass in Godot.
        const wantsOutline =
          !isEye &&
          !isMouth &&
          shouldApplyShader &&
          (shaderType === "unshaded" || shaderType === "gold" || shaderType === "angel");
        if (wantsOutline) {
          const oc: unknown = equippedSkin?.skinConfig?.outline_color;
          let outlineColor: THREE.Color | number = 0x000000;
          if (shaderType !== "unshaded") {
            if (Array.isArray(oc) && oc.length >= 3) {
              outlineColor = new THREE.Color(Number(oc[0]) || 0, Number(oc[1]) || 0, Number(oc[2]) || 0);
            } else if (typeof oc === "string") {
              outlineColor = new THREE.Color(oc);
            }
          }
          const outlineMat = new THREE.MeshBasicMaterial({
            color: outlineColor,
            side: THREE.BackSide,
          });
          const outlineGeo = child.geometry.clone();
          let outlineMesh: THREE.Mesh;
          if (child instanceof THREE.SkinnedMesh) {
            outlineMesh = new THREE.SkinnedMesh(outlineGeo, outlineMat);
            (outlineMesh as THREE.SkinnedMesh).skeleton = child.skeleton;
            (outlineMesh as THREE.SkinnedMesh).bindMatrix = child.bindMatrix;
            (outlineMesh as THREE.SkinnedMesh).bindMatrixInverse = child.bindMatrixInverse;
          } else {
            outlineMesh = new THREE.Mesh(outlineGeo, outlineMat);
          }
          outlineMesh.position.copy(child.position);
          outlineMesh.quaternion.copy(child.quaternion);
          // Every outline pass Godot draws uses size 1.04, so scale the
          // stand-in mesh by the same factor.
          const baseScale = 1.04;
          outlineMesh.scale.copy(child.scale).multiplyScalar(baseScale);
          outlineMesh.renderOrder = -1;
          child.parent?.add(outlineMesh);
          outlineMeshesRef.current.push(outlineMesh);
        }
      }
    });

    return () => {
      toonGradient.dispose();
      disposeOutlineMeshes();
    };
  }, [model, equippedSkin]);

  // Bone attachment logic (legacy: one primitive shaped by attachment.shape)ape)
  useEffect(() => {
    // Skins that name real attachments (["duck", "hair_001", ...]) are dressed
    // by the manifest-driven effect below. Only old configs that set
    // attachment.shape come through here.
    if (Array.isArray(equippedSkin?.skinConfig?.attachments)) return;
    let headBone: THREE.Object3D | null = null;
    model.traverse((child) => {
      if (child instanceof THREE.Bone) {
        const name = child.name;
        if (name === "mixamorig_Head" || name.toLowerCase().includes("head")) {
          headBone = child;
        }
      }
    });

    if (headBone) {
      // Remove existing attachment if any
      const existing = headBone.getObjectByName("bone-attachment");
      if (existing) {
        headBone.remove(existing);
        // Explicitly dispose to prevent leaks
        if (existing instanceof THREE.Mesh) {
          existing.geometry.dispose();
          if (Array.isArray(existing.material)) {
            existing.material.forEach(m => m.dispose());
          } else {
            existing.material.dispose();
          }
        }
      }

      const attachmentCfg = equippedSkin?.skinConfig?.attachment || {};
      const legacyShape = equippedSkin?.skinConfig?.attachmentShape;
      const attachmentShape = attachmentCfg.shape || legacyShape;
      if (!attachmentShape) return;

      const shape = attachmentShape;
      const isModel = shape.endsWith(".fbx");

      let currentAttachment: THREE.Object3D | null = null;
      let isCleanup = false;

      const applyThemeToMesh = (mesh: THREE.Mesh, skinConfig: any) => {
        const shaderType = skinConfig.shader || "default";
        const targets = skinConfig.shaderTargets || ["body", "cheek", "eye", "attachment"];
        const shouldApplyShader = targets.includes("attachment");

        let material: THREE.Material;

        const pal = skinConfig.palette || {};
        const attColor = skinConfig.attachment?.color || skinConfig.attachmentColor || pal.skin || skinConfig.color || "red";
        if (shouldApplyShader && shaderType !== "default") {
          if (shaderType === "ghost") {
            material = new THREE.MeshStandardMaterial({ color: attColor });
            material.transparent = true;
            material.opacity = 0.6;
            material.depthWrite = true;
            if (material instanceof THREE.MeshStandardMaterial) {
              material.roughness = 0.1;
            }
          } else if (shaderType === "gold") {
            material = new THREE.MeshStandardMaterial({
              color: attColor,
              metalness: 1.0,
              roughness: 0.1
            });
          } else if (shaderType === "shadow" || shaderType === "void") {
            material = new THREE.MeshBasicMaterial({
              color: 0x000000,
              depthWrite: shaderType === "void" ? false : true,
              transparent: shaderType === "void" ? true : false,
            });
          } else if (shaderType === "angel") {
            material = new THREE.MeshStandardMaterial({
              color: attColor,
              metalness: 1.0,
              roughness: 0.1
            });
          } else {
            material = new THREE.MeshStandardMaterial({ color: attColor });
          }
        } else {
          const pal = skinConfig.palette || {};
          const attachmentColor = new THREE.Color(skinConfig.attachment?.color || skinConfig.attachmentColor || pal.skin || skinConfig.color || "#ff2496");
          material = new THREE.MeshToonMaterial({
            color: attachmentColor,
            gradientMap: createToonGradientTexture(4),
          });
        }

        if (shouldApplyShader) {
          const rawFrag = skinConfig.rawFragmentShader;
          const rawVert = skinConfig.rawVertexShader;
          if (rawFrag || rawVert) {
            material.onBeforeCompile = (shader) => {
              shader.uniforms.uTime = { value: 0 };
              if (rawFrag) {
                shader.fragmentShader = `uniform float uTime;\n` + shader.fragmentShader.replace(
                  '#include <dithering_fragment>',
                  `#include <dithering_fragment>\n${rawFrag}`
                );
              }
              if (rawVert) {
                shader.vertexShader = `uniform float uTime;\n` + shader.vertexShader.replace(
                  '#include <project_vertex>',
                  `#include <project_vertex>\n${rawVert}`
                );
              }
              material.userData.shader = shader;
            };
            animatedMaterialsRef.current.push(material);
          }
        }
        mesh.material = material;
      };

      const setupAttachment = (obj: THREE.Object3D, shapeType?: string) => {
        obj.name = "bone-attachment";
        // Apply materials to all meshes in the model
        obj.traverse((child) => {
          if (child instanceof THREE.Mesh) {
            applyThemeToMesh(child, equippedSkin.skinConfig);
          }
        });

        if (shapeType === "torus") {
          obj.scale.setScalar(0.012);
          obj.position.set(0, -1.72, -0.02);
          obj.rotation.set(Math.PI / 2, 0, 0);
        } else if (shapeType === "cylinder") {
          obj.scale.setScalar(0.0135);
          obj.position.set(0, -1.78, 0.0);
          obj.rotation.set(0, 0, Math.PI / 2);
        } else {
          obj.scale.setScalar(0.0085);
          obj.position.set(0, -2.10, -0.05);
        }
        headBone.add(obj);
        currentAttachment = obj;
      };

      if (isModel) {
        const loader = new FBXLoader();
        loader.load(shape, (fbx) => {
          if (isCleanup) return;
          setupAttachment(fbx, shape);
        });
      } else {
        let geometry: THREE.BufferGeometry;
        switch (shape) {
          case "cone":
            geometry = new THREE.ConeGeometry(60, 120, 32);
            break;
          case "sphere":
            geometry = new THREE.SphereGeometry(60, 32, 32);
            break;
          case "cylinder":
            geometry = new THREE.CylinderGeometry(50, 50, 100, 32);
            break;
          case "torus":
            geometry = new THREE.TorusGeometry(55, 18, 24, 48);
            break;
          case "box":
          default:
            geometry = new THREE.BoxGeometry(100, 100, 100);
            break;
        }
        const mesh = new THREE.Mesh(geometry);
        setupAttachment(mesh, shape);
      }

      return () => {
        isCleanup = true;
        if (currentAttachment) {
          headBone.remove(currentAttachment);
          currentAttachment.traverse((child) => {
            if (child instanceof THREE.Mesh) {
              child.geometry.dispose();
              if (Array.isArray(child.material)) {
                child.material.forEach(m => m.dispose());
              } else {
                child.material.dispose();
              }
            }
          });
        }
      };
    }
  }, [model, equippedSkin]);

  // Named attachment list: dress the nad exactly like the game does.
  useEffect(() => {
    const list = equippedSkin?.skinConfig?.attachments;
    if (!Array.isArray(list) || list.length === 0) return;

    let disposed = false;
    const placed: THREE.Object3D[] = [];
    const shaderType = resolveShaderType(equippedSkin?.id, equippedSkin?.skinConfig?.shader);
    const madeMaterials: THREE.Material[] = [];
    const madeOutlines: THREE.Mesh[] = [];

    // The unshaded edition draws the body flat with a black 1.04 outline, so
    // its attachments have to follow or the hat and duck read shaded and bare
    // against a flat body. Mirrors SkinApplier._apply_attachment_shader: the
    // authored colour and texture carry over, only the lighting model changes.
    const applyUnshadedLook = (root: THREE.Object3D) => {
      // Snapshot first: outlines are added to the tree while we work, and a
      // live traverse would pick them up and outline the outlines.
      const meshes: THREE.Mesh[] = [];
      root.traverse((c) => {
        if (c instanceof THREE.Mesh && !c.userData.isAttachmentOutline) meshes.push(c);
      });
      for (const child of meshes) {
        const src = Array.isArray(child.material) ? child.material[0] : child.material;
        const srcStd = src as THREE.MeshStandardMaterial;
        // The prototype's material is shared with the cache, so it is swapped
        // out here, never mutated or disposed - only what we create is disposed.
        const flat = new THREE.MeshBasicMaterial({
          color: srcStd.color ? srcStd.color.clone() : new THREE.Color(0xffffff),
          map: srcStd.map ?? null,
          transparent: src.transparent,
          opacity: src.opacity,
        });
        madeMaterials.push(flat);
        child.material = flat;

        const outlineMat = new THREE.MeshBasicMaterial({
          color: 0x000000,
          side: THREE.BackSide,
        });
        madeMaterials.push(outlineMat);
        const outlineGeo = child.geometry.clone();
        let outlineMesh: THREE.Mesh;
        if (child instanceof THREE.SkinnedMesh) {
          const skinned = new THREE.SkinnedMesh(outlineGeo, outlineMat);
          skinned.skeleton = child.skeleton;
          skinned.bindMatrix = child.bindMatrix;
          skinned.bindMatrixInverse = child.bindMatrixInverse;
          outlineMesh = skinned;
        } else {
          outlineMesh = new THREE.Mesh(outlineGeo, outlineMat);
        }
        outlineMesh.name = "attachment-outline";
        outlineMesh.userData.isAttachmentOutline = true;
        outlineMesh.position.copy(child.position);
        outlineMesh.quaternion.copy(child.quaternion);
        outlineMesh.scale.copy(child.scale).multiplyScalar(1.04);
        outlineMesh.renderOrder = -1;
        child.parent?.add(outlineMesh);
        madeOutlines.push(outlineMesh);
      }
    };

    (async () => {
      const manifest = await loadAttachmentManifest();
      if (disposed || !manifest) {
        if (!manifest) {
          console.warn("[ThreeScene] /attachments/manifest.json missing - run tools/export_attachments.gd");
        }
        return;
      }
      for (const name of list) {
        const entry = manifest[name];
        if (!entry) {
          console.warn(`[ThreeScene] skin references unknown attachment "${name}"`);
          continue;
        }
        const bone = findBone(model, entry.bone);
        if (!bone) {
          console.warn(`[ThreeScene] bone "${entry.bone}" missing for attachment "${name}"`);
          continue;
        }
        const prototype = await loadAttachment(entry.file);
        if (disposed || !prototype) continue;
        // Clone per instance: the cached prototype stays pristine when the
        // skin changes again. Transforms come straight from the GLB.
        const obj = prototype.clone(true);
        obj.name = `attachment-${name}`;
        if (shaderType === "unshaded") applyUnshadedLook(obj);
        bone.add(obj);
        placed.push(obj);
      }
    })();

    return () => {
      disposed = true;
      for (const outline of madeOutlines) {
        outline.parent?.remove(outline);
        outline.geometry.dispose();
      }
      for (const mat of madeMaterials) mat.dispose();
      for (const obj of placed) {
        obj.parent?.remove(obj);
      }
      placed.length = 0;
    };
  }, [model, equippedSkin]);

  

  // Overall model cleanup on unmount
  useEffect(() => {
    return () => {
      disposeOutlineMeshes();
      model.traverse((child) => {
        if (child instanceof THREE.Mesh) {
          // Dispose of any temporary material clones created during skin selection
          if (child.material && child.material !== child.userData.originalMaterial) {
            child.material.dispose();
          }
        }
      });
    };
  }, [model]);

  useEffect(() => {
    if (!model.animations || model.animations.length === 0) return;
    const action = mixer.clipAction(model.animations[0]);
    action.play();
    return () => mixer.stopAllAction();
  }, [mixer, model.animations]);

  useFrame((state, delta) => {
    mixer.update(delta);

    const clockTime = state.clock.getElapsedTime();
    for (const mat of animatedMaterialsRef.current) {
      const shader = mat.userData?.shader;
      if (!shader) continue;
      if (!shader.uniforms.uTime) {
        shader.uniforms.uTime = { value: 0 };
      }
      shader.uniforms.uTime.value = clockTime;
    }
  });

  return (
    <primitive
      object={model}
      position={position}
      rotation={rotation}
      scale={scale}
    />
  );
};

// --- Main Scene Component ---
export const ThreeScene: React.FC<ThreeSceneProps> = React.memo(({
  equippedSkin,
}) => {
  const controlsRef = useRef<any>(null);
  const glRef = useRef<THREE.WebGLRenderer | null>(null);
  const cameraRef = useRef<THREE.PerspectiveCamera | null>(null);
  const invalidateRef = useRef<(() => void) | null>(null);

  // Raise the camera and the orbit target by the same amount: this pans the
  // framing up so the nad sits lower and its head clears the top edge.
  // Raising only the target would tilt the camera further up at the nad.
  // Mobile portrait keeps the full lift for headroom; landscape and
  // desktop give back 10% so the legs stay inside the frame.
  const MOBILE_LIFT = 0.5;
  const DESKTOP_LIFT = 0.45;

  const getCameraLift = () =>
    window.innerWidth < 768 && window.innerHeight > window.innerWidth
      ? MOBILE_LIFT
      : DESKTOP_LIFT;

  const [cameraZ, setCameraZ] = useState(() =>
    window.innerWidth < 768 ? 9 : 10
  );
  const [cameraLift, setCameraLift] = useState(getCameraLift);
  const [targetY, setTargetY] = useState(() =>
    (window.innerWidth < 768 ? 1.4 : 1.5) + getCameraLift()
  );

  // Force the orbit target on the controls so a fresh load always frames
  // the scene the same way (props-only application can get skipped with
  // frameloop="demand").
  useEffect(() => {
    const controls = controlsRef.current;
    if (controls) {
      controls.target.set(0, targetY, 0);
      controls.update();
    }
  }, [targetY]);

  // Chrome fullscreens by changing the layout, and with frameloop="demand"
  // the canvas can keep its old projection after the transition, which pushes
  // the whole scene off-center and scales it wrong. Re-derive the camera
  // aspect from the actual canvas box after entering/exiting fullscreen and
  // force a re-render (timers mirror App.tsx's fullscreenchange handling).
  useEffect(() => {
    const resyncCamera = () => {
      const gl = glRef.current;
      const cam = cameraRef.current;
      const canvas = gl?.domElement;
      if (!gl || !cam || !canvas) return;

      const apply = () => {
        const w = canvas.clientWidth;
        const h = canvas.clientHeight;
        if (!w || !h) return;
        cam.aspect = w / h;
        cam.updateProjectionMatrix();
        controlsRef.current?.update();
        invalidateRef.current?.();
      };

      apply();
      const timers: number[] = [];
      [120, 400].forEach((ms) => {
        timers.push(window.setTimeout(apply, ms));
      });
      return () => timers.forEach((t) => clearTimeout(t));
    };

    document.addEventListener("fullscreenchange", resyncCamera);
    document.addEventListener("webkitfullscreenchange", resyncCamera);
    return () => {
      document.removeEventListener("fullscreenchange", resyncCamera);
      document.removeEventListener("webkitfullscreenchange", resyncCamera);
    };
  }, []);

  useEffect(() => {
    const handleResize = () => {
      const mobile = window.innerWidth < 768;
      // Z=10 provides a consistent zoom level for both mobile and desktop
      setCameraZ(mobile ? 9 : 10);
      // Raise the camera target so the nad/chickens sit lower on screen,
      // and keep the camera and target lifted together
      const lift = getCameraLift();
      setCameraLift(lift);
      setTargetY((mobile ? 1.4 : 1.5) + lift);
    };
    window.addEventListener("resize", handleResize);
    window.addEventListener("orientationchange", handleResize);
    return () => {
      window.removeEventListener("resize", handleResize);
      window.removeEventListener("orientationchange", handleResize);
    };
  }, []);

  const chickenCount = 6;
  const radius = 6;
  const seed = 12345;
  const rand = (s: number) => () => {
    s = (s * 1664525 + 1013904223) % 4294967296;
    return s / 4294967296;
  };
  const random = rand(seed);

  const chickens = useMemo(() => {
    return Array.from({ length: chickenCount }).map((_, i) => {
      const theta = random() * 2 * Math.PI;
      const phi = Math.acos(2 * random() - 1);

      return {
        key: i,
        position: [
          radius * Math.sin(phi) * Math.cos(theta),
          radius * Math.sin(phi) * Math.sin(theta),
          radius * Math.cos(phi),
        ] as [number, number, number],
        rotation: [
          random() * 2 * Math.PI,
          random() * 2 * Math.PI,
          random() * 2 * Math.PI,
        ] as [number, number, number],
        scale: 2 + random() * 2,
      };
    });
  }, []);

  return (
    <Canvas
      dpr={[1, 1.35]}
      camera={{ position: [0, cameraLift, cameraZ] }}
      frameloop="demand"
      gl={{ alpha: true, powerPreference: "high-performance", antialias: true }}
      style={{ background: "none", pointerEvents: "auto" }}
      onCreated={({ gl, camera, invalidate }) => {
        gl.setClearColor(0x000000, 0);
        glRef.current = gl;
        cameraRef.current = camera as THREE.PerspectiveCamera;
        invalidateRef.current = invalidate;
      }}
    >
      <ambientLight intensity={1.5} />
      {/* Professional Three-Point Lighting Setup */}
      {/* Key Light: Strong primary light */}
      <directionalLight position={[10, 10, 10]} intensity={2.5} />
      {/* Fill Light: Softens shadows from the key light */}
      <directionalLight position={[-10, 5, 5]} intensity={1.5} />
      {/* Rim Light: Provides highlights on the edges (separated from BG) */}
      <pointLight position={[0, 10, -10]} intensity={3.5} />

      <Environment resolution={64} frames={1}>
        <Lightformer intensity={4} rotation-x={Math.PI / 2} position={[0, 5, -9]} scale={[10, 10, 1]} />
        <Lightformer intensity={2.5} rotation-y={Math.PI / 2} position={[-5, 1, -1]} scale={[20, 0.5, 1]} />
        <Lightformer intensity={2} rotation-y={-Math.PI / 2} position={[10, 1, 0]} scale={[20, 1, 1]} />
        <Lightformer form="ring" intensity={3} position={[0, 2, 0]} scale={[2, 2, 1]} />
      </Environment>

      <Suspense fallback={null}>
        <NadModel scale={0.5} position={[0, -2, 0]} equippedSkin={equippedSkin} />



        {chickens.map((data) => (
          <Chicken key={data.key} {...data} />
        ))}
      </Suspense>

      <OrbitControls
        ref={controlsRef}
        target={[0, targetY, 0]}
        enableZoom={true}
        enablePan={false}
        enableRotate={true}
        mouseButtons={{
          LEFT: THREE.MOUSE.ROTATE,
          MIDDLE: null as any,
          RIGHT: null as any,
        }}
      />
    </Canvas>
  );
});
