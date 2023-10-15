import React, { useRef, useEffect } from 'react';
import './Rossler.css';

const ParticleBackground = () => {
    const canvasRef = useRef(null);

    useEffect(() => {
        const canvas = canvasRef.current;
        const ctx = canvas.getContext('2d');
        canvas.width = window.innerWidth * 0.8;
        canvas.height = window.innerHeight * 0.8;

        const particles = [
            {
                attractor: {
                    x: 1,
                    y: -11,
                    z: 14,
                    dt: 0.01,
                    a: 0.2,
                    b: 0.2,
                    c: 5.7,
                },
                color: '0, 102, 0', // green
                trail: [],
            },
            {
                attractor: {
                    x: -0.2,
                    y: 12,
                    z: -0.01,
                    dt: 0.01,
                    a: 0.2,
                    b: 0.2,
                    c: 5.7,
                },
                color: '255, 153, 0', // orange
                trail: [],
            },
            {
                attractor: {
                    x: 13,
                    y: 6,
                    z: 24,
                    dt: 0.01,
                    a: 0.2,
                    b: 0.2,
                    c: 5.7,
                },
                color: '102, 0, 255', // purple
                trail: [],
            },
        ];


        const updateParticles = () => {
            ctx.clearRect(0, 0, canvas.width, canvas.height); // Clear the canvas on each frame

            particles.forEach((rossler) => {
                const { x, y, z, dt, a, b, c } = rossler.attractor;
                const dx = (-y - z) * dt * 2;
                const dy = (x + a * y) * dt * 2;
                const dz = (b + z * (x - c)) * dt * 2;

                rossler.attractor.x += dx;
                rossler.attractor.y += dy;
                rossler.attractor.z += dz;

                // Update rossler position based on the attractor
                const newTrailPoint = {
                    x: canvas.width / 2 + rossler.attractor.x * 5,
                    y: canvas.height / 2 + rossler.attractor.z * 5,
                };
                rossler.trail.push(newTrailPoint);

                // Limit the trail length to create the fading effect
                if (rossler.trail.length > 500) {
                    rossler.trail.shift();
                }

                // Draw fading track with dynamic color and longer-lasting effect
                ctx.beginPath();
                ctx.moveTo(rossler.trail[0].x, rossler.trail[0].y);
                for (let i = 1; i < rossler.trail.length; i++) {
                    const point = rossler.trail[i];
                    ctx.lineTo(point.x, point.y);
                }
                ctx.strokeStyle = `rgba(${rossler.color}, 0.5)`;
                ctx.lineWidth = 4;
                ctx.stroke();

                // Draw rossler head as a smaller circle
                const lastTrailPoint = rossler.trail[rossler.trail.length - 1];
                ctx.beginPath();
                ctx.arc(lastTrailPoint.x, lastTrailPoint.y, 2, 0, Math.PI * 2); // Smaller radius
                ctx.fillStyle = `rgba(${rossler.color}, 1)`;
                ctx.fill();
            });

            requestAnimationFrame(updateParticles);
        };

        updateParticles();

        return () => {
            // Cleanup logic, if necessary
        };
    }, []);

    return <canvas ref={canvasRef} className="Rossler" />;
};

export default ParticleBackground;
