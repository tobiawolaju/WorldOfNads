// src/components/AvatarScene.tsx
import { Canvas } from "@react-three/fiber";
import { OrbitControls } from "@react-three/drei";

export default function AvatarScene() {
  return (
    <div style={{ width: "100%", height: "100%" }}>
      <Canvas camera={{ position: [3, 3, 3] }}>
        {/* Lights */}
        <ambientLight intensity={1.0} />
        <directionalLight position={[5, 5, 5]} intensity={1} />

        {/* Character Placeholder */}
        <mesh rotation={[0.4, 0.8, 0]}>
          <boxGeometry args={[1, 2, 1]} />
          <meshStandardMaterial color="#ee00ffff" />
        </mesh>

        <OrbitControls enablePan={false} enableZoom={false} />
      </Canvas>
    </div>
  );
}