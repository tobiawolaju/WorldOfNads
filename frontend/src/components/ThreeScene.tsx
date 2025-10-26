import React, { Suspense, useEffect, useState } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
import { IdCard } from "./IdCard";

function Model() {
  const model = useFBX("/banana.fbx");
  return (
    <primitive
      object={model}
      scale={0.02}
      position={[0, 0, 0]}
      rotation={[0, Math.PI / 2, 0]}
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
  const [cameraZ, setCameraZ] = useState(10); // default desktop

  useEffect(() => {
    const handleResize = () => {
      if (window.innerWidth < 768) {
        setCameraZ(14); // 📱 mobile
      } else {
        setCameraZ(18); // 🖥 desktop
      }
    };

    handleResize(); // run once
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  return (
    <Canvas camera={{ position: [0, 0, cameraZ] }}>
      <ambientLight intensity={2} />
      <directionalLight position={[5, 5, 5]} intensity={2} />

      <Suspense fallback={null}>
        <Model />
      </Suspense>

      <IdCard twitter={twitter} wallets={wallets} earned={earned} onLogout={onLogout} />

      <OrbitControls
        enableZoom={false}
        minAzimuthAngle={-Math.PI / 2}
        maxAzimuthAngle={Math.PI / 2}
        minPolarAngle={Math.PI / 4}
        maxPolarAngle={(3 * Math.PI) / 4}
      />
    </Canvas>
  );
};
