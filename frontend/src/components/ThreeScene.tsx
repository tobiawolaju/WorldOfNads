import React, { Suspense, useEffect, useState } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, useFBX, Html } from "@react-three/drei";
import { IdCard } from "./IdCard";
import CardRig from "./CardRig";
import * as THREE from "three";

interface ChickenProps {
  position: [number, number, number];
  rotation: [number, number, number];
  scale?: number;
}

const Chicken: React.FC<ChickenProps> = ({ position, rotation, scale = 10 }) => {
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

interface Props {
  twitter: any;
  wallets: any[];
  earned: number;
  onLogout: () => void;
  radius?: number; // 👈 optional prop (default spacing)
}

export const ThreeScene: React.FC<Props> = ({
  twitter,
  wallets,
  earned,
  onLogout,
  radius = 14, // 👈 default cube radius
}) => {
  const [cameraZ, setCameraZ] = useState(10);

  useEffect(() => {
    const handleResize = () => {
      setCameraZ(window.innerWidth < 768 ? 14 : 18);
    };
    handleResize();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  return (
<Canvas
  dpr={[1, 2]}
  camera={{ position: [0, 0, cameraZ] }}
  gl={{ alpha: true, preserveDrawingBuffer: true }} // 👈 add this
  style={{
    background: "none",          // ✅ 'none' works better than 'transparent'
    pointerEvents: "auto",
  }}
  onCreated={({ gl }) => {
    gl.setClearColor(0x000000, 0);
  }}
>



      <ambientLight intensity={3} />
      <directionalLight position={[5, 5, 5]} intensity={1.0} />

      <Suspense fallback={null}>
        {/* === Chickens arranged around card (cube-style) === */}
        <Chicken position={[radius, 0, 0]} rotation={[0, -Math.PI / 2, 0]} scale={10} />  {/* +X */}
        <Chicken position={[-radius, 0, 0]} rotation={[0, Math.PI / 2, 0]} scale={8} />   {/* -X */}
        <Chicken position={[0, radius, 0]} rotation={[Math.PI / 2, 0, 0]} scale={6} />    {/* +Y */}
        <Chicken position={[0, -radius, 0]} rotation={[-Math.PI / 2, 0, 0]} scale={9} />  {/* -Y */}
        <Chicken position={[0, -6, radius]} rotation={[0, Math.PI, 0]} scale={11} />       {/* +Z */}
        <Chicken position={[0, 5, -radius]} rotation={[0, 0, 0]} scale={7} />             {/* -Z */}

        {/* === Center Card === */}
        <CardRig>
          <IdCard
            twitter={twitter}
            wallets={wallets}
            earned={earned}
            onLogout={onLogout}
          />
        </CardRig>
      </Suspense>


     <OrbitControls
  enableZoom ={false}
  minPolarAngle={(Math.PI / 2) +0.2}   // 👈 90° — horizontal view
  maxPolarAngle={Math.PI / 2}  
  
  autoRotate={true}             // 👈 enables smooth automatic rotation
  autoRotateSpeed={-1.2}  
/>

    </Canvas>
  );
};
