import React, { Suspense, useEffect, useMemo, useRef, useState } from "react";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { OrbitControls, useFBX, Environment, ContactShadows } from "@react-three/drei";
import { FBXLoader } from "three/examples/jsm/loaders/FBXLoader.js";
import * as SkeletonUtils from "three/examples/jsm/utils/SkeletonUtils.js";
import * as THREE from "three";

import CardRig from "./CardRig";
import { IdCard } from "./IdCard";

// --- Prop Types ---
interface SocialAccount {
  provider: string;
  profilePictureUrl?: string;
  name?: string;
  username?: string;
}

interface Wallet {
  address: string;
}

interface SkinConfig {
  attachmentShape?: "box" | "cone" | "sphere" | "cylinder" | "torus";
  color?: string;
  cheekColor?: string;
  attachmentColor?: string;
  shader?: "ghost" | "gold" | "shadow" | "angel" | "default" | "void";
  shaderTargets?: ("body" | "cheek" | "eye" | "attachment")[];
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
  social?: SocialAccount;
  wallets: Wallet[];
  earned: number;
  username: string;
  onLogout: () => void;
  equippedSkin?: StoreItem | null;
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
  const fbx = useFBX("/Chicken.fbx");
  const model = useMemo(() => fbx.clone(), [fbx]);
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

  // Handle character color change
  useEffect(() => {
    const baseColorHex = equippedSkin?.skinConfig?.color || "#ff2496";
    const baseColor = new THREE.Color(baseColorHex);

    // Use explicit cheekColor if provided, otherwise lerp to white (subtler)
    const cheekColor = equippedSkin?.skinConfig?.cheekColor
      ? new THREE.Color(equippedSkin.skinConfig.cheekColor)
      : baseColor.clone().lerp(new THREE.Color("#ffffff"), 0.15);

    const eyeColorHex = equippedSkin?.skinConfig?.eyeColor || "#ffffff";
    const eyeColor = new THREE.Color(eyeColorHex);

    model.traverse((child) => {
      if (child instanceof THREE.Mesh && child.name !== "bone-attachment") {
        // Store original material if not already stored
        if (!child.userData.originalMaterial) {
          child.userData.originalMaterial = child.material;
        }

        // Start with a fresh clone of the original material
        let newMat: THREE.Material = child.userData.originalMaterial.clone();

        const name = child.name;
        const isHeadOrBody = /^Cube$|Cube[._]?00[123]$/.test(name);
        const isCheek = /Cube[._]?00[45]$/.test(name);
        const isEye = /Cube[._]?00[67]$/.test(name);
        const partName = isHeadOrBody ? "body" : isCheek ? "cheek" : isEye ? "eye" : "unknown";

        const shaderType = equippedSkin?.skinConfig?.shader || "default";
        const targets = equippedSkin?.skinConfig?.shaderTargets || ["body", "cheek", "eye", "attachment"];
        const shouldApplyShader = targets.includes(partName as any);

        // Apply Custom Shader Logic
        if (shouldApplyShader) {
          if (shaderType === "ghost") {
            newMat.transparent = true;
            newMat.opacity = 0.6;
            newMat.depthWrite = true;
            if ((newMat as any).roughness !== undefined) {
              (newMat as any).roughness = 0.1;
            }
          } else if (shaderType === "gold") {
            // Material upgrade to MeshStandardMaterial if needed to support metallic/roughness
            if (newMat.type !== "MeshStandardMaterial") {
              const oldColor = (newMat as any).color ? (newMat as any).color.clone() : new THREE.Color("#ffd700");
              const oldMap = (newMat as any).map;
              newMat = new THREE.MeshStandardMaterial({
                color: oldColor,
                map: oldMap,
                metalness: 1.0,
                roughness: 0.1
              });
            } else {
              (newMat as THREE.MeshStandardMaterial).metalness = 1.0;
              (newMat as THREE.MeshStandardMaterial).roughness = 0.1;
            }
          } else if (shaderType === "shadow" || shaderType === "void") {
            newMat = new THREE.MeshBasicMaterial({
              depthWrite: shaderType === "void" ? false : true,
              transparent: shaderType === "void" ? true : false,
            });
          } else if (shaderType === "angel") {
            if (partName === "eye" && (newMat as any).emissive !== undefined) {
              (newMat as any).emissive = eyeColor.clone();
              (newMat as any).emissiveIntensity = 1.0;
            }
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
          }
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
      }
    });
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

      if (!equippedSkin?.skinConfig?.attachmentShape) return;

      const shape = equippedSkin.skinConfig.attachmentShape;
      const isModel = shape.endsWith(".fbx");

      let currentAttachment: THREE.Object3D | null = null;
      let isCleanup = false;

      const applyThemeToMesh = (mesh: THREE.Mesh, skinConfig: any) => {
        let material: THREE.Material = new THREE.MeshStandardMaterial({
          color: skinConfig.attachmentColor || skinConfig.color || "red"
        });

        const shaderType = skinConfig.shader || "default";
        const targets = skinConfig.shaderTargets || ["body", "cheek", "eye", "attachment"];
        const shouldApplyShader = targets.includes("attachment");

        if (shouldApplyShader) {
          if (shaderType === "ghost") {
            material.transparent = true;
            material.opacity = 0.6;
            material.depthWrite = true;
            if (material instanceof THREE.MeshStandardMaterial) {
              material.roughness = 0.1;
            }
          } else if (shaderType === "gold") {
            if (material instanceof THREE.MeshStandardMaterial) {
              material.metalness = 1.0;
              material.roughness = 0.1;
            }
          } else if (shaderType === "shadow" || shaderType === "void") {
            material = new THREE.MeshBasicMaterial({
              color: 0x000000,
              depthWrite: shaderType === "void" ? false : true,
              transparent: shaderType === "void" ? true : false,
            });
          } else if (shaderType === "angel") {
            if (material instanceof THREE.MeshStandardMaterial) {
              material.metalness = 1.0;
              material.roughness = 0.1;
              material.color.set(skinConfig.attachmentColor || "#ffd700");
            }
          }

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

    // Invalidate the frame to ensure animations continue rendering in "demand" modo
    state.invalidate();

    const clockTime = state.clock.getElapsedTime();
    model.traverse((child) => {
      if (child instanceof THREE.Mesh && child.material) {
        const mat = child.material as THREE.Material;
        if (mat.userData?.shader) {
          if (!mat.userData.shader.uniforms.uTime) {
            mat.userData.shader.uniforms.uTime = { value: 0 };
          }
          mat.userData.shader.uniforms.uTime.value = clockTime;
        }
      }
    });
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
const CameraAnimator: React.FC<{ isInteracting: boolean; baseDistance: number; targetY: number; cameraYOffset: number }> = ({ isInteracting: propIsInteracting, baseDistance, targetY, cameraYOffset }) => {
  const { camera, controls, gl } = useThree();
  const [phase, setPhase] = useState<'intro' | 'pendulum'>('intro');
  const [introStartTime] = useState(Date.now());
  const [pendulumState, setPendulumState] = useState({
    basePosition: new THREE.Vector3(0, 2, baseDistance),
    startTime: 0
  });

  const [isWheelInteracting, setIsWheelInteracting] = useState(false);
  const wheelTimeout = useRef<any>(null);

  useEffect(() => {
    const handleWheel = () => {
      setIsWheelInteracting(true);
      if (wheelTimeout.current) clearTimeout(wheelTimeout.current);
      wheelTimeout.current = setTimeout(() => {
        setIsWheelInteracting(false);
      }, 250);
    };

    const domElement = gl.domElement;
    domElement.addEventListener('wheel', handleWheel, { passive: true });
    return () => {
      domElement.removeEventListener('wheel', handleWheel);
      if (wheelTimeout.current) clearTimeout(wheelTimeout.current);
    };
  }, [gl.domElement]);

  const isInteracting = propIsInteracting || isWheelInteracting;

  // Track if we were interacting in the previous frame
  const wasInteracting = useRef(isInteracting);

  useFrame(() => {
    if (isInteracting) {
      // While interacting, continuously capture the raw camera position
      setPendulumState({
        basePosition: camera.position.clone(),
        startTime: Date.now()
      });
      setPhase('pendulum');
      wasInteracting.current = true;
      return;
    }

    // On user interaction release, do a final state capture for absolute precision
    if (wasInteracting.current && !isInteracting) {
      setPendulumState({
        basePosition: camera.position.clone(),
        startTime: Date.now()
      });
      wasInteracting.current = false;
    }

    const now = Date.now();

    if (phase === 'intro') {
      const duration = 5000;
      const elapsed = now - introStartTime;
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
        setPhase('pendulum');
        setPendulumState({
          basePosition: camera.position.clone(),
          startTime: now
        });
      }
    } else if (phase === 'pendulum') {
      const elapsed = (now - pendulumState.startTime) / 1000;
      // Oscillate +/- 18 degrees
      const oscillation = Math.sin(elapsed * 0.4) * (18 * Math.PI / 180);

      const axis = new THREE.Vector3(0, 1, 0);
      const newPos = pendulumState.basePosition.clone();
      newPos.applyAxisAngle(axis, oscillation);

      camera.position.copy(newPos);
      camera.lookAt(0, targetY, 0);
    }

    if (controls) (controls as any).update();
  });

  return null;
};

// --- Main Scene Component ---
export const ThreeScene: React.FC<ThreeSceneProps> = ({
  social,
  wallets,
  earned,
  username,
  onLogout,
  equippedSkin,
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
      dpr={[1, 1.5]}
      camera={{ position: [0, 0, cameraZ] }}
      frameloop="demand"
      gl={{ alpha: true, preserveDrawingBuffer: true, powerPreference: "high-performance", antialias: true }}
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
        resolution={128}
        color="#000000"
        position={[0, -2.01, 0]}
      />

      <Suspense fallback={null}>
        <NadModel scale={0.5} position={[0, -2, 0]} equippedSkin={equippedSkin} />

        <CardRig>
          <group rotation={[-0.5, 1, 1]} position={[4, 0.5, 0]} scale={0.3}>
            <IdCard
              social={social}
              wallets={wallets}
              earned={earned}
              username={username}
              onLogout={onLogout}
              lightweight={false}
            />
          </group>
        </CardRig>

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

      <CameraAnimator isInteracting={isInteracting} baseDistance={cameraZ} targetY={targetY} cameraYOffset={cameraYOffset} />
    </Canvas>
  );
};
