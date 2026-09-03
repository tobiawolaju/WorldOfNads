import React, { Suspense, useEffect, useMemo, useRef, useState } from "react";
import { Canvas, useFrame, useLoader, useThree } from "@react-three/fiber";
import { OrbitControls, useFBX, Environment, ContactShadows } from "@react-three/drei";
import { FBXLoader } from "three/examples/jsm/loaders/FBXLoader.js";
import { OBJLoader } from "three/examples/jsm/loaders/OBJLoader.js";
import * as SkeletonUtils from "three/examples/jsm/utils/SkeletonUtils.js";
import * as THREE from "three";

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
  shader?: "ghost" | "gold" | "shadow" | "angel" | "default" | "void";
  shaderTargets?: ("body" | "cheek" | "eye" | "attachment")[];
  attachment?: AttachmentConfig;
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
    canvas.width = 8;
    canvas.height = 64;
    const ctx = canvas.getContext('2d')!;
    const gradient = ctx.createLinearGradient(0, 0, 0, 64);
    for (let i = 0; i < steps; i++) {
      const t = i / (steps - 1);
      const val = Math.floor(t * 255);
      gradient.addColorStop(t, `rgb(${val},${val},${val})`);
    }
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, 8, 64);
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

        const shaderType = equippedSkin?.skinConfig?.shader || "default";
        const targets = equippedSkin?.skinConfig?.shaderTargets || ["body", "cheek", "eye", "attachment"];
        const shouldApplyShader = targets.includes(isHeadOrBody ? "body" : isCheek ? "cheek" : isEye ? "eye" : "unknown");

        let newMat: THREE.Material;

        // Apply Custom Shader Logic
        if (shouldApplyShader && shaderType !== "default") {
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
        if (rawFrag || rawVert) {
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
          if ((child.material as any).color) (child.material as any).color.copy(eyeColor);
        }

        // Create outline mesh for this part
        if (shaderType === "default" || !shouldApplyShader) {
          const outlineMat = new THREE.MeshBasicMaterial({
            color: 0x000000,
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
          const baseScale = shaderType === "default" ? 1.04 : 1.0;
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

  // Bone attachment logic
  useEffect(() => {
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

// --- Camera Animation Logic ---
const CameraAnimator: React.FC<{
  isInteracting: boolean;
  baseDistance: number;
  targetY: number;
  cameraYOffset: number;
  isStoreOpen: boolean;
  controlsRef: React.RefObject<any>;
}> = ({ isInteracting: propIsInteracting, baseDistance, targetY, cameraYOffset, isStoreOpen, controlsRef }) => {
  const { camera, gl } = useThree();
  const phaseRef = useRef<'intro' | 'pendulum'>('intro');
  const introStartTimeRef = useRef(Date.now());
  const pendulumStateRef = useRef({
    basePosition: new THREE.Vector3(0, 2, baseDistance),
    startTime: 0
  });
  const storeLockRef = useRef<{
    active: boolean;
    position: THREE.Vector3;
    target: THREE.Vector3;
    zoom: number;
    enableZoom: boolean;
    enabled: boolean;
  }>({
    active: false,
    position: new THREE.Vector3(),
    target: new THREE.Vector3(),
    zoom: 1,
    enableZoom: true,
    enabled: true
  });
  const propIsInteractingRef = useRef(propIsInteracting);
  const wasInteractingRef = useRef(propIsInteracting);
  const wheelInteractingRef = useRef(false);
  const wheelTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    propIsInteractingRef.current = propIsInteracting;
  }, [propIsInteracting]);

  useEffect(() => {
    pendulumStateRef.current.basePosition = new THREE.Vector3(0, 2, baseDistance);
  }, [baseDistance]);

  useEffect(() => {
    const controls = controlsRef.current;
    if (!controls) return;

    if (isStoreOpen) {
      if (!storeLockRef.current.active) {
        storeLockRef.current.position.copy(camera.position);
        storeLockRef.current.target.copy(controls.target);
        storeLockRef.current.zoom = camera.zoom;
        storeLockRef.current.enableZoom = controls.enableZoom;
        storeLockRef.current.enabled = controls.enabled;
        storeLockRef.current.active = true;
      }

      const direction = camera.position.clone().sub(controls.target);
      if (direction.lengthSq() === 0) {
        direction.set(0, 0, 1);
      }
      direction.normalize();

      const lockedPosition = controls.target.clone().add(direction.multiplyScalar(2.647));
      camera.position.copy(lockedPosition);
      camera.zoom = 1;
      camera.updateProjectionMatrix();
      camera.lookAt(controls.target);
      controls.enableZoom = false;
      controls.enabled = true;
      controls.update();
      return;
    }

    if (storeLockRef.current.active) {
      camera.position.copy(storeLockRef.current.position);
      camera.zoom = storeLockRef.current.zoom;
      camera.updateProjectionMatrix();
      controls.target.copy(storeLockRef.current.target);
      controls.enableZoom = storeLockRef.current.enableZoom;
      controls.enabled = storeLockRef.current.enabled;
      camera.lookAt(storeLockRef.current.target);
      controls.update();
      storeLockRef.current.active = false;
    }
  }, [camera, controlsRef, isStoreOpen]);

  useEffect(() => {
    const handleWheel = () => {
      wheelInteractingRef.current = true;
      if (wheelTimeout.current) clearTimeout(wheelTimeout.current);
      wheelTimeout.current = setTimeout(() => {
        wheelInteractingRef.current = false;
      }, 250);
    };

    const domElement = gl.domElement;
    domElement.addEventListener('wheel', handleWheel, { passive: true });
    return () => {
      domElement.removeEventListener('wheel', handleWheel);
      if (wheelTimeout.current) clearTimeout(wheelTimeout.current);
    };
  }, [gl.domElement]);

  useFrame(() => {
    const controls = controlsRef.current;
    if (controls) {
      if (isStoreOpen) {
        if (!storeLockRef.current.active) {
          storeLockRef.current.position.copy(camera.position);
          storeLockRef.current.target.copy(controls.target);
          storeLockRef.current.zoom = camera.zoom;
          storeLockRef.current.enableZoom = controls.enableZoom;
          storeLockRef.current.enabled = controls.enabled;
          storeLockRef.current.active = true;
        }

        const direction = camera.position.clone().sub(controls.target);
        if (direction.lengthSq() === 0) {
          direction.set(0, 0, 1);
        }
        direction.normalize();

        const lockedPosition = controls.target.clone().add(direction.multiplyScalar(2.647));
        camera.position.copy(lockedPosition);
        camera.zoom = 1;
        camera.updateProjectionMatrix();
        camera.lookAt(controls.target);
        controls.enableZoom = false;
        controls.enabled = true;
        controls.update();
        return;
      }

      if (storeLockRef.current.active) {
        camera.position.copy(storeLockRef.current.position);
        camera.zoom = storeLockRef.current.zoom;
        camera.updateProjectionMatrix();
        controls.target.copy(storeLockRef.current.target);
        controls.enableZoom = storeLockRef.current.enableZoom;
        controls.enabled = storeLockRef.current.enabled;
        camera.lookAt(storeLockRef.current.target);
        controls.update();
        storeLockRef.current.active = false;
      }
    }

    if (isStoreOpen) {
      return;
    }

    const isInteracting = propIsInteractingRef.current || wheelInteractingRef.current;

    if (isInteracting) {
      pendulumStateRef.current.basePosition = camera.position.clone();
      pendulumStateRef.current.startTime = Date.now();
      phaseRef.current = 'pendulum';
      wasInteractingRef.current = true;
      return;
    }

    // On user interaction release, do a final state capture for absolute precision
    if (wasInteractingRef.current && !isInteracting) {
      pendulumStateRef.current.basePosition = camera.position.clone();
      pendulumStateRef.current.startTime = Date.now();
      wasInteractingRef.current = false;
    }

    const now = Date.now();

    if (phaseRef.current === 'intro') {
      const duration = 5000;
      const elapsed = now - introStartTimeRef.current;
      const progress = Math.min(elapsed / duration, 1);

      // 360 Spin logic
      const angle = progress * Math.PI * 2;

      // Starts at the old end zoom (60% of baseDistance) 
      const startDistance = baseDistance * 0.6;
      // Ends even closer to the center (40% of baseDistance)
      const endDistance = baseDistance * 0.4;

      // Smoothly interpolate between start and end distance
      const currentBaseDist = startDistance - (startDistance - endDistance) * progress;

      // Add a pull-back effect during the middle of the 360 spin
      const pullBackEffect = Math.sin(progress * Math.PI) * (baseDistance * 1.2);

      const distance = currentBaseDist + pullBackEffect;

      camera.position.x = Math.sin(angle) * distance;
      camera.position.z = Math.cos(angle) * distance;

      // Calculate a ratio (1.0 at origin distance, ~0.3 at closest zoom)
      const heightRatio = distance / baseDistance;
      // Slopes from ~1.8 (high) down to ~ -0.3 (low front view)
      camera.position.y = (heightRatio * 3) - 1.2 + cameraYOffset;
      camera.lookAt(0, targetY, 0);

      if (progress >= 1) {
        phaseRef.current = 'pendulum';
        pendulumStateRef.current.basePosition = camera.position.clone();
        pendulumStateRef.current.startTime = now;
      }
    } else if (phaseRef.current === 'pendulum') {
      const elapsed = (now - pendulumStateRef.current.startTime) / 1000;
      // Oscillate +/- 18 degrees
      const oscillation = Math.sin(elapsed * 0.4) * (18 * Math.PI / 180);

      const axis = new THREE.Vector3(0, 1, 0);
      const newPos = pendulumStateRef.current.basePosition.clone();
      newPos.applyAxisAngle(axis, oscillation);

      camera.position.copy(newPos);
      camera.lookAt(0, targetY, 0);
    }

    if (controls) (controls as any).update();
  });

  return null;
};

const CameraInteractionLogger: React.FC<{ controlsRef: React.RefObject<any>; baseDistance: number }> = ({ controlsRef, baseDistance }) => {
  const { camera } = useThree();
  const isInteractingRef = useRef(false);
  const wheelTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const controls = controlsRef.current;
    if (!controls?.addEventListener) return;

    const handleStart = () => {
      isInteractingRef.current = true;
    };

    const handleEnd = () => {
      isInteractingRef.current = false;
    };

    const handleWheel = () => {
      isInteractingRef.current = true;
      if (wheelTimeoutRef.current) clearTimeout(wheelTimeoutRef.current);
      wheelTimeoutRef.current = setTimeout(() => {
        isInteractingRef.current = false;
      }, 250);
    };

    const domElement = controls.domElement as HTMLElement | undefined;

    controls.addEventListener("start", handleStart);
    controls.addEventListener("end", handleEnd);
    domElement?.addEventListener("wheel", handleWheel, { passive: true });

    return () => {
      if (wheelTimeoutRef.current) clearTimeout(wheelTimeoutRef.current);
      controls.removeEventListener("start", handleStart);
      controls.removeEventListener("end", handleEnd);
      domElement?.removeEventListener("wheel", handleWheel);
    };
  }, [baseDistance, camera, controlsRef]);

  return null;
};

// --- Main Scene Component ---
export const ThreeScene: React.FC<ThreeSceneProps> = ({
  equippedSkin,
  isStoreOpen = false,
}) => {
  const [cameraZ, setCameraZ] = useState(22);
  const [targetY, setTargetY] = useState(0);
  const [cameraYOffset, setCameraYOffset] = useState(0);
  const [isInteracting, setIsInteracting] = useState(false);

  useEffect(() => {
    const handleResize = () => {
      const mobile = window.innerWidth < 768;
      // Z=10 provides a consistent zoom level for both mobile and desktop
      setCameraZ(mobile ? 9 : 10);
      // Moving target up by +0.25 (half the head-to-shadow distance)
      // Original: 0.5, New: 0.75
      setTargetY(mobile ? 0.7 : 0.75);
      setCameraYOffset(mobile ? 0.65 : 0.75);
    };
    handleResize();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  const controlsRef = useRef<any>(null);

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
      camera={{ position: [0, 0, cameraZ] }}
      frameloop="demand"
      gl={{ alpha: true, powerPreference: "high-performance", antialias: true }}
      style={{ background: "none", pointerEvents: "auto" }}
      onCreated={({ gl }) => gl.setClearColor(0x000000, 0)}
    >
      <ambientLight intensity={1.5} />
      {/* Professional Three-Point Lighting Setup */}
      {/* Key Light: Strong primary light */}
      <directionalLight position={[10, 10, 10]} intensity={2.5} />
      {/* Fill Light: Softens shadows from the key light */}
      <directionalLight position={[-10, 5, 5]} intensity={1.5} />
      {/* Rim Light: Provides highlights on the edges (separated from BG) */}
      <pointLight position={[0, 10, -10]} intensity={3.5} />

      <Environment preset="city" />
      <ContactShadows
        opacity={0.35}
        scale={6}
        blur={1.5}
        far={4}
        resolution={64}
        color="#000000"
        position={[0, -2.01, 0]}
      />

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
        onStart={() => setIsInteracting(true)}
        onEnd={() => setIsInteracting(false)}
        mouseButtons={{
          LEFT: THREE.MOUSE.ROTATE,
          MIDDLE: null as any,
          RIGHT: null as any,
        }}
      />

      <CameraInteractionLogger controlsRef={controlsRef} baseDistance={cameraZ} />
      <CameraAnimator isInteracting={isInteracting} baseDistance={cameraZ} targetY={targetY} cameraYOffset={cameraYOffset} isStoreOpen={isStoreOpen} controlsRef={controlsRef} />
    </Canvas>
  );
};
