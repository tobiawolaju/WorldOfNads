import React, { Suspense, useEffect, useMemo, useState, useRef } from "react";
import { Canvas, useFrame } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
import * as THREE from "three";
import CardRig from "./CardRig";
import { IdCard } from "./IdCard";

// --- Prop Types (No changes here) ---
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

// --- Chicken Component (No changes here) ---
interface ChickenProps {
  position: [number, number, number];
  rotation: [number, number, number];
  scale?: number;
}
const Chicken: React.FC<ChickenProps> = ({ position, rotation, scale = 15 }) => {
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

// --- Component to add subtle rotation oscillation ---
const SubtleRotation: React.FC<{ controlsRef: React.RefObject<OrbitControls> }> = ({ controlsRef }) => {
  const time = useRef(0);

  // Amplitude in radians (0.5 degrees is very small)
  const rotationAmplitudeX = THREE.MathUtils.degToRad(0.5);
  const rotationAmplitudeY = THREE.MathUtils.degToRad(0.5);
  
  // Phase offset for Y rotation to make it slightly different from X
  const rotationPhaseYOffset = Math.PI / 4; // Offset by 45 degrees

  useFrame((state, delta) => {
    if (controlsRef.current) {
      time.current += delta;

      // Calculate sine wave rotation
      const oscillationX = Math.sin(time.current * 0.5) * rotationAmplitudeX; // Slower oscillation
      const oscillationY = Math.sin(time.current * 0.5 + rotationPhaseYOffset) * rotationAmplitudeY; // Slower oscillation with phase offset

      // Apply the oscillation to the existing rotation from OrbitControls
      // We are modifying the target rotation of the controls
      controlsRef.current.target.rotation.x = controlsRef.current.target.rotation.x + oscillationX;
      controlsRef.current.target.rotation.y = controlsRef.current.target.rotation.y + oscillationY;
      
      // Ensure the target rotation doesn't go too wild
      controlsRef.current.target.rotation.x = THREE.MathUtils.clamp(controlsRef.current.target.rotation.x, -0.2, 0.2);
      controlsRef.current.target.rotation.y = THREE.MathUtils.clamp(controlsRef.current.target.rotation.y, -0.2, 0.2);

      // Update the camera's rotation based on the target's rotation
      state.camera.lookAt(controlsRef.current.target.position);
    }
  });

  return null; // This component doesn't render anything itself
};


// --- Main Scene Component ---
export const ThreeScene: React.FC<ThreeSceneProps> = ({ twitter, wallets, earned, onLogout }) => {
  const [cameraZ, setCameraZ] = useState(18);
  const orbitControlsRef = useRef<OrbitControls>(null); // Ref for OrbitControls

  useEffect(() => {
    const handleResize = () => {
      setCameraZ(window.innerWidth < 768 ? 24 : 18);
    };
    handleResize();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  const chickenCount = 6;
  const radius = 12;
  const randomSeed = 12345;

  const createRandomGenerator = (seed: number) => {
      return () => {
          seed = (seed * 1664525 + 1013904223) % 4294967296;
          return seed / 4294967296;
      };
  };

  const chickens = useMemo(() => {
      const random = createRandomGenerator(randomSeed);
      return Array.from({ length: chickenCount }).map((_, i) => {
          const theta = random() * 2 * Math.PI;
          const phi = Math.acos(2 * random() - 1);

          const x = radius * Math.sin(phi) * Math.cos(theta);
          const y = radius * Math.sin(phi) * Math.sin(theta);
          const z = radius * Math.cos(phi);

          const rotX = random() * 2 * Math.PI;
          const rotY = random() * 2 * Math.PI;
          const rotZ = random() * 2 * Math.PI;
          
          const scale = 5 + random() * 5;

          return {
              key: i,
              position: [x, y, z] as [number, number, number],
              rotation: [rotX, rotY, rotZ] as [number, number, number],
              scale: scale,
          };
      });
  }, [chickenCount, radius, randomSeed]);

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
        <CardRig>
          <IdCard
            twitter={twitter}
            wallets={wallets}
            earned={earned}
            onLogout={onLogout}
          />
        </CardRig>
        
        {chickens.map(chickenProps => (
          <Chicken {...chickenProps} />
        ))}
      </Suspense>

      {/* --- MODIFIED OrbitControls --- */}
      <OrbitControls
        ref={orbitControlsRef}
        enableZoom={false}
        autoRotate={false}
        // Set a minimum and maximum rotation to keep the oscillation contained
        minPolarAngle={Math.PI / 4} // Prevent looking too far down
        maxPolarAngle={Math.PI - Math.PI / 4} // Prevent looking too far up
        minAzimuthAngle={-Infinity} // Allow full horizontal rotation
        maxAzimuthAngle={Infinity}
        rotateSpeed={0.2} // Adjust this to control manual rotation speed
      />

      {/* --- NEW: Add the subtle rotation component --- */}
      {orbitControlsRef.current && <SubtleRotation controlsRef={orbitControlsRef} />}
    </Canvas>
  );
};