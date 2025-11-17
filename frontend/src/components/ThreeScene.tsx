import React, { Suspense, useState, useEffect } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
import * as THREE from "three";

// --- Nad Model Component (raw import, no transform) ---
const NadModel: React.FC = () => {
  const fbx = useFBX("/nad.fbx");
  const model = fbx.clone();

  return <primitive object={model} />;
};

// --- Main Scene ---
export const ThreeScene: React.FC = () => {
  const [cameraZ, setCameraZ] = useState(50);

  useEffect(() => {
    const handleResize = () => setCameraZ(50);
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
      <directionalLight position={[5, 5, 5]} intensity={1.0} />

      <Suspense fallback={null}>
        <NadModel />
      </Suspense>

      <OrbitControls
        enableZoom={true}
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
