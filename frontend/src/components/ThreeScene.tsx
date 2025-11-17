import React, { Suspense, useEffect, useMemo, useState } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
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

// --- Chicken Component ---
interface ChickenProps {
  position: [number, number, number];
  rotation: [number, number, number];
  scale?: number;
}
const Chicken: React.FC<ChickenProps> = ({ position, rotation, scale = 15 }) => {
  const fbx = useFBX("/Chicken.fbx");
  const model = fbx.clone();
  return (
    <primitive
      object={model}
      position={position}
      rotation={rotation}
      scale={new THREE.Vector3(scale, scale, scale)}
    />
  );
};

// --- Nad Model Component ---
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
  const fbx = useFBX("/Nad.fbx");
  const model = fbx.clone();
  return (
    <primitive
      object={model}
      position={position}
      rotation={rotation}
      scale={new THREE.Vector3(scale, scale, scale)}
    />
  );
};

// --- Main Scene Component ---
export const ThreeScene: React.FC<ThreeSceneProps> = ({ twitter, wallets, earned, onLogout }) => {
  const [cameraZ, setCameraZ] = useState(22);

  useEffect(() => {
    const handleResize = () => {
      setCameraZ(window.innerWidth < 768 ? 22 : 20);
    };
    handleResize();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  // --- Chicken setup ---
  const chickenCount = 6;
  const radius = 12; 
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

      const scale = 5 + random() * 5;

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
        {/* Center Nad Model */}
        <NadModel scale={0.1} /> 

        {/* Offset ID Card slightly along Z */}
        <CardRig>
          <group position={[0, 0, 3]}> {/* Adjust this offset as needed */}
            <IdCard
              twitter={twitter}
              wallets={wallets}
              earned={earned}
              onLogout={onLogout}
            />
          </group>
        </CardRig>

        {/* Chickens around */}
        {chickens.map(chickenProps => (
          <Chicken {...chickenProps} />
        ))}
      </Suspense>

      <OrbitControls
        enableZoom={false}
        enablePan={false}
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
