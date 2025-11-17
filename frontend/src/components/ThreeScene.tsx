import React, { Suspense, useEffect, useState } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
import * as THREE from "three";

// === SIMPLE MODEL COMPONENT ===
const NadModel = () => {
  const model = useFBX("/nad.fbx"); // auto loads once

  // Apply simple scale
  model.scale.set(0.5, 0.5, 0.5);
  model.position.set(0,0,0);

  return <primitive object={model} />;
};

// === MAIN SCENE ===
export const ThreeScene = ({ twitter, wallets, earned, onLogout }) => {
  const [cameraZ, setCameraZ] = useState(22);

  useEffect(() => {
    const handleResize = () => {
      setCameraZ(window.innerWidth < 768 ? 2 : 1);
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
      style={{ background: "none", pointerEvents: "auto" }}
      onCreated={({ gl }) => gl.setClearColor(0x000000, 0)}
    >
      <ambientLight intensity={3} />
      <directionalLight intensity={1} position={[5, 5, 5]} />

      <Suspense fallback={null}>
        <NadModel />
      </Suspense>

      <OrbitControls
        enableZoom={false}
        enablePan={false}
        enableRotate={true}
        mouseButtons={{
          LEFT: THREE.MOUSE.ROTATE,
          RIGHT: null,
          MIDDLE: null,
        }}
      />
    </Canvas>
  );
};
