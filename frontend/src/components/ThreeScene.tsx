import React, { Suspense } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
import { IdCard } from "./IdCard";

function Model() {
  const model = useFBX("/banana.fbx"); // ✅ must be in public/banana.fbx

  return (
    <primitive 
      object={model}
      scale={0.02}                 // ⬆️ increase scale so it's visible
      position={[0, 0, 0]}      // ⬇️ move it down slightly
      rotation={[0, Math.PI / 2, 0]} // ⬅️ rotate if sideways
    />
  );
}


interface Props {
  twitter: any;
  wallets: any[];
  earned: number;
  onLogout: () => void;
}

export const ThreeScene: React.FC<Props> = ({ twitter, wallets, earned, onLogout }) => {
  return (
    <Canvas camera={{ position: [0, 0, 18] }}>  {/* ⬆️ move camera back */}
      <ambientLight intensity={2} />
      <directionalLight position={[5, 5, 5]} intensity={2} />

      <Suspense fallback={null}>
        <Model />
      </Suspense>


      <IdCard twitter={twitter} wallets={wallets} earned={earned} onLogout={onLogout} />

      <OrbitControls enableZoom={false} />
    </Canvas>
  );
};





