import React, { Suspense, useEffect, useMemo, useRef, useState } from "react";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
import * as SkeletonUtils from "three/examples/jsm/utils/SkeletonUtils.js";
import * as THREE from "three";

import CardRig from "./CardRig";
import { IdCard } from "./IdCard";

// --- Prop Types ---
interface Twitter {
  profilePictureUrl?: string;
  name?: string;
  username?: string;
}

interface Wallet {
  address: string;
}

interface ThreeSceneProps {
  twitter?: Twitter;
  wallets: Wallet[];
  earned: number;
  username: string;
  onLogout: () => void;
}

// 🟢 HOOK — select object and orbit camera to it
const useSelectToOrbit = () => {
  const controlsRef = useRef<any>(null);

  const onSelect = (obj: THREE.Object3D) => {
    if (!obj || !controlsRef.current) return;

    const center = new THREE.Vector3();
    obj.getWorldPosition(center);

    controlsRef.current.target.copy(center);
    controlsRef.current.update();
  };

  return { controlsRef, onSelect };
};

// --- Shader Definition for Water Bubble Effect ---
const vertexShader = `
  varying vec3 vNormal;
  varying vec3 vViewPosition;
  void main() {
    vec4 modelViewPosition = modelViewMatrix * vec4(position, 1.0);
    vViewPosition = -modelViewPosition.xyz;
    vNormal = normalize(normalMatrix * normal);
    gl_Position = projectionMatrix * modelViewPosition;
  }
`;

const fragmentShader = `
  uniform float uTime;
  varying vec3 vNormal;
  varying vec3 vViewPosition;
  void main() {
    vec3 viewDir = normalize(vViewPosition);
    float fresnel = 1.0 - dot(viewDir, vNormal);
    fresnel = pow(fresnel, 2.5);

    vec3 color;
    color.r = sin(fresnel * 5.0 - uTime * 0.5) * 0.5 + 0.5;
    color.g = sin(fresnel * 5.0 - uTime * 0.5 + 2.094) * 0.5 + 0.5;
    color.b = sin(fresnel * 5.0 - uTime * 0.5 + 4.188) * 0.5 + 0.5;

    gl_FragColor = vec4(color, fresnel * 0.8);
  }
`;

// --- Chicken Component with Shader ---
interface ChickenProps {
  position: [number, number, number];
  rotation: [number, number, number];
  scale?: number;
  onSelect: (obj: THREE.Object3D) => void;
}
const Chicken: React.FC<ChickenProps> = ({
  position,
  rotation,
  scale = 6,
  onSelect,
}) => {
  const fbx = useFBX("/Chicken.fbx");
  const model = useMemo(() => fbx.clone(), [fbx]);
  const shaderRef = useRef<THREE.ShaderMaterial>(null);

  useFrame(({ clock }) => {
    if (shaderRef.current) {
      shaderRef.current.uniforms.uTime.value = clock.getElapsedTime();
    }
  });

  useEffect(() => {
    const bubbleMaterial = new THREE.ShaderMaterial({
      uniforms: { uTime: { value: 0 } },
      vertexShader,
      fragmentShader,
      transparent: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      })
    shaderRef.current = bubbleMaterial;
    model.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        child.material = bubbleMaterial;
      }
    });
  }, [model]);

  return (
    <primitive
      object={model}
      position={position}
      rotation={rotation}
      scale={scale}
      onClick={(e: any) => {
        e.stopPropagation();
        onSelect(model);
      }}
    />
  );
};

// --- Animated Nad Model Component ---
interface NadModelProps {
  position?: [number, number, number];
  rotation?: [number, number, number];
  scale?: number;
  onSelect: (obj: THREE.Object3D) => void;
}
const NadModel: React.FC<NadModelProps> = ({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  onSelect,
}) => {
  const fbx = useFBX("/nad.fbx");
  const model = useMemo(() => SkeletonUtils.clone(fbx), [fbx]);
  const mixer = useMemo(() => new THREE.AnimationMixer(model), [model]);

  useEffect(() => {
    const box = new THREE.Box3().setFromObject(model);
    const size = new THREE.Vector3();
    box.getSize(size);

    const maxDim = Math.max(size.x, size.y, size.z);
    if (maxDim > 0) {
      const s = 1 / maxDim;
      model.scale.setScalar(s);
    }

    const center = new THREE.Vector3();
    box.getCenter(center);
    model.position.sub(center.multiplyScalar(model.scale.x));
  }, [model]);

  useEffect(() => {
    if (!model.animations || model.animations.length === 0) return;
    const action = mixer.clipAction(model.animations[0]);
    action.play();
    return () => mixer.stopAllAction();
  }, [mixer, model.animations]);

  useFrame((_, delta) => mixer.update(delta));

  return (
    <primitive
      object={model}
      position={position}
      rotation={rotation}
      scale={scale}
      onClick={(e: any) => {
        e.stopPropagation();
        onSelect(model);
      }}
    />
  );
};

// --- Camera Animation Logic ---
const CameraAnimator: React.FC<{ isInteracting: boolean; baseDistance: number }> = ({ isInteracting, baseDistance }) => {
  const { camera, controls } = useThree();
  const [phase, setPhase] = useState<'intro' | 'pendulum'>('intro');
  const [introStartTime] = useState(Date.now());
  const [pendulumState, setPendulumState] = useState({
    basePosition: new THREE.Vector3(0, 2, baseDistance),
    startTime: 0
  });

  // Track if we were interacting in the previous frame
  const wasInteracting = useRef(isInteracting);

  useFrame(() => {
    if (isInteracting) {
      // While interacting, continuously capture the raw camera position
      setPendulumState({
        basePosition: camera.position.clone(),
        startTime: Date.now()
      });
      setPhase('pendulum'); 
      wasInteracting.current = true;
      return;
    }

    // On user interaction release, do a final state capture for absolute precision
    if (wasInteracting.current && !isInteracting) {
      setPendulumState({
        basePosition: camera.position.clone(),
        startTime: Date.now()
      });
      wasInteracting.current = false;
    }

    const now = Date.now();

    if (phase === 'intro') {
      const duration = 5000;
      const elapsed = now - introStartTime;
      const progress = Math.min(elapsed / duration, 1);

      // 360 Spin logic
      const angle = progress * Math.PI * 2;
      const zoomOutFactor = Math.sin(progress * Math.PI);
      const finalZoomFactor = progress * 0.4;
      const distance = baseDistance + (zoomOutFactor * baseDistance * 1.2) - (finalZoomFactor * baseDistance);

      camera.position.x = Math.sin(angle) * distance;
      camera.position.z = Math.cos(angle) * distance;
      camera.position.y = 2;
      camera.lookAt(0, 0, 0);

      if (progress >= 1) {
        setPhase('pendulum');
        setPendulumState({
          basePosition: camera.position.clone(),
          startTime: now
        });
      }
    } else if (phase === 'pendulum') {
      const elapsed = (now - pendulumState.startTime) / 1000;
      // Oscillate +/- 45 degrees
      const oscillation = Math.sin(elapsed * 0.4) * (Math.PI / 4);

      // Create rotation matrix for the oscillation around the Y axis
      const pivot = new THREE.Vector3(0, 0, 0);
      const axis = new THREE.Vector3(0, 1, 0);
      
      // We apply the rotation to the captured base position
      const newPos = pendulumState.basePosition.clone();
      newPos.applyAxisAngle(axis, oscillation);
      
      camera.position.copy(newPos);
      camera.lookAt(0, 0, 0);
    }

    if (controls) (controls as any).update();
  });

  return null;
};

// --- Main Scene Component ---
export const ThreeScene: React.FC<ThreeSceneProps> = ({
  twitter,
  wallets,
  earned,
  username,
  onLogout,
}) => {
  const [cameraZ, setCameraZ] = useState(22);
  const [isInteracting, setIsInteracting] = useState(false);

  useEffect(() => {
    const handleResize = () => {
      setCameraZ(window.innerWidth < 768 ? 10 : 8);
    };
    handleResize();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  const { controlsRef, onSelect } = useSelectToOrbit();

  const chickenCount = 6;
  const radius = 6;
  const seed = 12345;
  const rand = (s: number) => () => {
    s = (s * 1664525 + 1013904223) % 4294967296;
    return s / 4294967296;
  };
  const random = rand(seed);

  const chickens = useMemo(() => {
    return Array.from({ length: chickenCount }).map((_, i) => {
      const theta = random() * 2 * Math.PI;
      const phi = Math.acos(2 * random() - 1);

      return {
        key: i,
        position: [
          radius * Math.sin(phi) * Math.cos(theta),
          radius * Math.sin(phi) * Math.sin(theta),
          radius * Math.cos(phi),
        ] as [number, number, number],
        rotation: [
          random() * 2 * Math.PI,
          random() * 2 * Math.PI,
          random() * 2 * Math.PI,
        ] as [number, number, number],
        scale: 2 + random() * 2,
      };
    });
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
      <directionalLight position={[5, 5, 5]} intensity={1} />

      <Suspense fallback={null}>
        <NadModel scale={0.5} position={[0, -2, 0]} onSelect={onSelect} />

        <CardRig>
          <group rotation={[-0.5, 1, 1]} position={[4, 0.5, 0]} scale={0.3}>
            <IdCard
              twitter={twitter}
              wallets={wallets}
              earned={earned}
              username={username}
              onLogout={onLogout}
            />
          </group>
        </CardRig>

        {chickens.map((data) => (
          <Chicken key={data.key} {...data} onSelect={onSelect} />
        ))}
      </Suspense>

      <OrbitControls
        ref={controlsRef}
        enableZoom={true}
        enablePan={false}
        enableRotate={true}
        onStart={() => setIsInteracting(true)}
        onEnd={() => setIsInteracting(false)}
        mouseButtons={{
          LEFT: THREE.MOUSE.ROTATE,
          MIDDLE: null as any,
          RIGHT: null as any,
        }}
      />

      <CameraAnimator isInteracting={isInteracting} baseDistance={cameraZ} />
    </Canvas>
  );
};
