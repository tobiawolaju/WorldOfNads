import React, { Suspense, useEffect, useMemo, useState } from "react";
import { Canvas, useFrame } from "@react-three/fiber";
import { OrbitControls, useFBX } from "@react-three/drei";
import { SkeletonUtils } from "three/examples/jsm/utils/SkeletonUtils.js";
import * as THREE from "three";

// === MODEL COMPONENT ===
const NadModel = () => {
  const fbx = useFBX("/nad.fbx");

  // Clone FBX to fix skeleton issues
  const model = useMemo(() => SkeletonUtils.clone(fbx), [fbx]);

  // Mixer for animations
  const mixer = useMemo(() => new THREE.AnimationMixer(model), [model]);

  // Center & scale automatically
  useEffect(() => {
    // Compute bounding box
    const box = new THREE.Box3().setFromObject(model);
    const size = new THREE.Vector3();
    box.getSize(size);

    // Scale model to roughly 1 unit tall
    const maxDim = Math.max(size.x, size.y, size.z);
    const scaleFactor = 1 / maxDim;
    model.scale.setScalar(scaleFactor);

    // Center model at origin
    const center = new THREE.Vector3();
    box.getCenter(center);
    model.position.sub(center.multiplyScalar(scaleFactor));
  }, [model]);

  // Play first animation in loop
  useEffect(() => {
    if (!model.animations || model.animations.length === 0) {
      console.warn("No animations found in FBX");
      return;
    }

    console.log("Animations:", model.animations.map(a => a.name));

    const action = mixer.clipAction(model.animations[0]);
    action.loop = THREE.LoopRepeat;
    action.play();

    return () => mixer.stopAllAction();
  }, [model, mixer]);

  // Update mixer every frame
  useFrame((_, delta) => mixer.update(delta));

  return <primitive object={model} />;
};

// === MAIN SCENE ===
export const ThreeScene = ({ twitter, wallets, earned, onLogout }) => {
  const [cameraZ, setCameraZ] = useState(3);

  useEffect(() => {
    const handleResize = () =>
      setCameraZ(window.innerWidth < 768 ? 2 : 3);

    handleResize();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  return (
    <Canvas
      dpr={[1, 2]}
      camera={{ position: [0, 1.5, cameraZ], fov: 45 }}
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
        enableZoom={true}
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
