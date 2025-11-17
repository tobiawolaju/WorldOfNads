import React, { Suspense, useEffect, useState } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
import * as THREE from "three";

// --- Nad Model Component ---
interface NadModelProps {
  position?: [number, number, number];
  rotation?: [number, number, number];
  scale?: number; // additional multiplier
}
const NadModel: React.FC<NadModelProps> = ({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
}) => {
  const fbx = useFBX("/nad.fbx");
  const model = fbx.clone();

  React.useEffect(() => {
    // Disable frustum culling for safety
    model.traverse((child: any) => {
      if (child.isMesh) child.frustumCulled = false;
    });

    // Compute bounding box of the entire FBX
    const box = new THREE.Box3().setFromObject(model);
    const center = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());

    // Center model so all parts are around origin
    model.position.sub(center);

    // Scale model to reasonable size
    const maxSize = Math.max(size.x, size.y, size.z);
    const scaleFactor = 20 / maxSize; // Adjust "20" for visible size
    model.scale.setScalar(scale * scaleFactor);
  }, [model, scale]);

  return <primitive object={model} position={position} rotation={rotation} />;
};

// --- Main Scene ---
export const ThreeScene: React.FC = () => {
  const [cameraZ, setCameraZ] = useState(50);

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
        <NadModel scale={1} position={[0, 0, 0]} rotation={[0, 0, 0]} />
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
