import React, { Suspense, useEffect, useState } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
import * as THREE from "three";

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

export const ThreeScene: React.FC = () => {
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
        {/* 🐔 Single Chicken at Center */}
        <Chicken position={[0, 0, 0]} rotation={[0, Math.PI, 0]} scale={10} />
      </Suspense>

      {/* 🧭 OrbitControls - manual rotation only, zoom disabled */}
      <OrbitControls enableZoom={false} autoRotate={false} />
    </Canvas>
  );
};
