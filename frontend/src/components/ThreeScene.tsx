import React, { Suspense, useEffect, useState } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
import * as THREE from "three";

// --- Nad Model Component ---
interface NadModelProps {
  position?: [number, number, number];
  rotation?: [number, number, number];
  scale?: number;
}
const NadModel: React.FC<NadModelProps> = ({
  position = [0, 0, 15],
  rotation = [0, 2, 0],
  scale = 10,
}) => {
  const fbx = useFBX("/nad.fbx");
  const model = fbx.clone();

  // Only disable frustum culling; don't move or translate meshes
  React.useEffect(() => {
    model.traverse((child: any) => {
      if (child.isMesh) {
        child.frustumCulled = false;
      }
    });
  }, [model]);

  return (
    <primitive
      object={model}
      position={position}
      rotation={rotation}
      scale={new THREE.Vector3(scale, scale, scale)}
    />
  );
};

// --- Main Scene ---
export const ThreeScene: React.FC = () => {
  const [cameraZ, setCameraZ] = useState(50); // pull back to see big Nad

  useEffect(() => {
    const handleResize = () => {
      setCameraZ(window.innerWidth < 768 ? 50 : 50);
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
      onCreated={({ gl }) => {
        gl.setClearColor(0x000000, 0);
      }}
    >
      <ambientLight intensity={3} />
      <directionalLight position={[5, 5, 5]} intensity={1.0} />

      <Suspense fallback={null}>
        <NadModel scale={10} position={[0, 0, 15]} rotation={[0, 2, 0]} />
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