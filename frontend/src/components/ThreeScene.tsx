import React, { Suspense, useEffect, useMemo, useRef, useState } from "react";
import { Canvas, useFrame } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
import * as SkeletonUtils from 'three/examples/jsm/utils/SkeletonUtils.js';
import * as THREE from "three";

import CardRig from "./CardRig";
import { IdCard } from "./IdCard";

// --- Prop Types ---
interface Twitter {
  profilePictureUrl?: string;
  name?: string;
  username?: string;
}

interface Wallet {
  address: string;
}

interface ThreeSceneProps {
  twitter: Twitter | undefined;
  wallets: Wallet[];
  earned: number;
  onLogout: () => void;
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
  uniform float uTime;
  varying vec3 vNormal;
  varying vec3 vViewPosition;
  void main() {
    vec3 viewDir = normalize(vViewPosition);
    float fresnel = 1.0 - dot(viewDir, vNormal);
    fresnel = pow(fresnel, 2.5); // Increase power for sharper edge
    
    // Rainbow color effect driven by fresnel and time
    vec3 color;
    color.r = sin(fresnel * 5.0 - uTime * 0.5) * 0.5 + 0.5;
    color.g = sin(fresnel * 5.0 - uTime * 0.5 + 2.094) * 0.5 + 0.5; // 120 degrees offset
    color.b = sin(fresnel * 5.0 - uTime * 0.5 + 4.188) * 0.5 + 0.5; // 240 degrees offset
    
    // Final color with transparency
    gl_FragColor = vec4(color, fresnel * 0.8);
  }
`;


// --- Chicken Component with Shader ---
interface ChickenProps {
  position: [number, number, number];
  rotation: [number, number, number];
  scale?: number;
}
const Chicken: React.FC<ChickenProps> = ({ position, rotation, scale = 6 }) => {
  const fbx = useFBX("/Chicken.fbx");
  const model = useMemo(() => fbx.clone(), [fbx]);
  const shaderRef = useRef<THREE.ShaderMaterial>(null);

  // Animate the shader uniforms
  useFrame(({ clock }) => {
    if (shaderRef.current) {
      shaderRef.current.uniforms.uTime.value = clock.getElapsedTime();
    }
  });

  // Create and apply the shader material to the model
  useEffect(() => {
    const bubbleMaterial = new THREE.ShaderMaterial({
      uniforms: {
        uTime: { value: 0 },
      },
      vertexShader,
      fragmentShader,
      transparent: true,
      blending: THREE.AdditiveBlending, // Gives a nice glowing effect
      depthWrite: false, // Important for transparency
    });
    
    // Assign the ref so useFrame can access it
    shaderRef.current = bubbleMaterial;

    model.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        child.material = bubbleMaterial;
      }
    });
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
}
const NadModel: React.FC<NadModelProps> = ({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
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
      const scaleFactor = 1 / maxDim;
      model.scale.setScalar(scaleFactor);
    }
    const center = new THREE.Vector3();
    box.getCenter(center);
    model.position.sub(center.multiplyScalar(model.scale.x));
  }, [model]);

  useEffect(() => {
    if (!model.animations || model.animations.length === 0) return;
    const action = mixer.clipAction(model.animations[0]);
    action.play();
    return () => mixer.stopAllAction();
  }, [mixer, model.animations]);

  useFrame((_, delta) => mixer.update(delta));

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
export const ThreeScene: React.FC<ThreeSceneProps> = ({ twitter, wallets, earned, onLogout }) => {
  const [cameraZ, setCameraZ] = useState(22);

  useEffect(() => {
    const handleResize = () => {
      setCameraZ(window.innerWidth < 768 ? 5 : 4);
    };
    handleResize();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  const chickenCount = 6;
  const radius = 6;
  const randomSeed = 12345;

  const createRandomGenerator = (seed: number) => () => {
    seed = (seed * 1664525 + 1013904223) % 4294967296;
    return seed / 4294967296;
  };

  const chickens = useMemo(() => {
    const random = createRandomGenerator(randomSeed);
    return Array.from({ length: chickenCount }).map((_, i) => {
      const theta = random() * 2 * Math.PI;
      const phi = Math.acos(2 * random() - 1);
      const x = radius * Math.sin(phi) * Math.cos(theta);
      const y = radius * Math.sin(phi) * Math.sin(theta);
      const z = radius * Math.cos(phi);
      const rotX = random() * 2 * Math.PI;
      const rotY = random() * 2 * Math.PI;
      const rotZ = random() * 2 * Math.PI;
      const scale = 2 + random() * 2;
      return {
        key: i,
        position: [x, y, z] as [number, number, number],
        rotation: [rotX, rotY, rotZ] as [number, number, number],
        scale,
      };
    });
  }, [chickenCount, radius, randomSeed]);

  return (
    <Canvas
      dpr={[1, 2]}
      camera={{ position: [0, 0, cameraZ] }}
      gl={{ alpha: true, preserveDrawingBuffer: true }}
      style={{ background: "none", pointerEvents: "auto" }}
      onCreated={({ gl }) => { gl.setClearColor(0x000000, 0); }}
    >
      <ambientLight intensity={3} />
      <directionalLight position={[5, 5, 5]} intensity={1.0} />

      <Suspense fallback={null}>
        <NadModel scale={0.5} position={[0, -2, 0]} />

        <CardRig>
          <group rotation={[-0.5,1,1]} position={[4, 0.5, 0]} scale={0.3}>
            <IdCard
              twitter={twitter}
              wallets={wallets}
              earned={earned}
              onLogout={onLogout}
            />
          </group>
        </CardRig>

        {chickens.map(chickenProps => (
          <Chicken {...chickenProps} />
        ))}
      </Suspense>

      <OrbitControls
        enableZoom={true}
        enablePan={true}
        enableRotate={true}
        mouseButtons={{
          LEFT: THREE.MOUSE.ROTATE,
          MIDDLE: null,
          RIGHT: null,
        }}
      />
    </Canvas>
  );
};