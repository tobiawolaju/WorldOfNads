import React, { Suspense, useEffect, useState } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
import * as THREE from "three";

// --- Import the components you created ---
import CardRig from "./CardRig"; 
import { IdCard } from "./IdCard";

// --- Define prop types for the component ---
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


// This component is fine, no changes needed here.
interface ChickenProps {
  position: [number, number, number];
  rotation: [number, number, number];
  scale?: number;
}
const Chicken: React.FC<ChickenProps> = ({ position, rotation, scale = 15}) => {
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


// --- Update the ThreeScene component to accept and use the props ---
export const ThreeScene: React.FC<ThreeSceneProps> = ({ twitter, wallets, earned, onLogout }) => {
  const [cameraZ, setCameraZ] = useState(18); // Default to desktop zoom

  useEffect(() => {
    const handleResize = () => {
      // Adjust camera zoom based on screen width
      setCameraZ(window.innerWidth < 768 ? 24 : 18);
    };
    handleResize();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

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
        {/* --- THIS IS THE PART THAT WAS MISSING --- */}
        {/* The CardRig provides the subtle follow-mouse effect */}
        <CardRig>
          {/* The IdCard displays the user data */}
          <IdCard 
            twitter={twitter} 
            wallets={wallets} 
            earned={earned} 
            onLogout={onLogout} 
          />
        </CardRig>
        
        {/* The Chicken was in the center [0,0,0], so it would block the card.
            I've commented it out. You can reposition it if you like. */}
        {/* <Chicken position={[5, 0, -5]} rotation={[0, Math.PI / 2, 0]} scale={10} /> */}
      </Suspense>

      {/* OrbitControls allow the user to rotate the scene */}
      <OrbitControls enableZoom={false} autoRotate={false} />
    </Canvas>
  );
};