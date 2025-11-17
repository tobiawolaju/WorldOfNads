import React, { Suspense, useEffect, useMemo, useState } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
import * as THREE from "three";
import CardRig from "./CardRig";
import { IdCard } from "./IdCard";

// --- Prop Types (No changes here) ---
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

// --- Chicken Component (No changes here) ---
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

  // --- NEW: Variables for chicken generation ---
  const chickenCount = 6;
  const radius = 12; // How far the chickens are from the center card
  const randomSeed = 12345; // A seed for deterministic randomness

  // A simple seedable pseudo-random number generator (LCG)
  const createRandomGenerator = (seed: number) => {
      return () => {
          seed = (seed * 1664525 + 1013904223) % 4294967296;
          return seed / 4294967296;
      };
  };

  // --- NEW: Generate chicken positions and rotations ---
  // useMemo ensures this expensive calculation only runs once.
  const chickens = useMemo(() => {
      const random = createRandomGenerator(randomSeed);
      return Array.from({ length: chickenCount }).map((_, i) => {
          // Generate random angles for spherical coordinates
          const theta = random() * 2 * Math.PI; // Azimuthal angle (0 to 2π)
          const phi = Math.acos(2 * random() - 1); // Polar angle (0 to π)

          // Convert spherical to Cartesian (x, y, z) coordinates
          const x = radius * Math.sin(phi) * Math.cos(theta);
          const y = radius * Math.sin(phi) * Math.sin(theta);
          const z = radius * Math.cos(phi);

          // Give each chicken a random rotation
          const rotX = random() * 2 * Math.PI;
          const rotY = random() * 2 * Math.PI;
          const rotZ = random() * 2 * Math.PI;
          
          // Give each chicken a slightly random scale for variety
          const scale = 5 + random() * 5; // Random scale between 5 and 10

          return {
              key: i,
              position: [x, y, z] as [number, number, number],
              rotation: [rotX, rotY, rotZ] as [number, number, number],
              scale: scale,
          };
      });
  }, [chickenCount, radius, randomSeed]); // Re-run if these variables change

  return (
    <Canvas
      dpr={[1, 2]}
      camera={{ position: [0, 0, cameraZ] }}
      gl={{ alpha: true, preserveDrawingBuffer: true }}
      style={{
        background: "none",
        pointerEvents: "auto",
      }}
      onCreated={({ gl }) => {
        gl.setClearColor(0x000000, 0);
      }}
    >
      <ambientLight intensity={3} />
      <directionalLight position={[5, 5, 5]} intensity={1.0} />

      <Suspense fallback={null}>
        {/* The central ID Card */}
        <CardRig>
          <IdCard
            twitter={twitter}
            wallets={wallets}
            earned={earned}
            onLogout={onLogout}
          />
        </CardRig>
        
        {/* --- NEW: Render the generated chickens --- */}
        {chickens.map(chickenProps => (
          <Chicken {...chickenProps} />
        ))}
      </Suspense>

      <OrbitControls enableZoom={true} autoRotate={false} />
    </Canvas>
  );
};