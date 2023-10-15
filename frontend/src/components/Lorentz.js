import React, { useRef, useEffect } from 'react';
import './Lorentz.css';

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
                    x: 2,
                    y: 3,
                    z: 13,
                    dt: 0.01,
                    sigma: 10,
                    rho: 28,
                    beta: 8 / 3,
                },
                color: '0, 102, 0', // green
                trail: [],
            },
            {
                attractor: {
                    x: 4,
                    y: -3,
                    z: -1,
                    dt: 0.01,
                    sigma: 10,
                    rho: 28,
                    beta: 8 / 3,
                },
                color: '255, 153, 0', // orange
                trail: [],
            },
            {
                attractor: {
                    x: 12,
                    y: -1,
                    z: 0,
                    dt: 0.01,
                    sigma: 10,
                    rho: 28,
                    beta: 8 / 3,
                },
                color: '102, 0, 255', // purple
                trail: [],
            },
        ];


        const updateParticles = () => {
            ctx.clearRect(0, 0, canvas.width, canvas.height);

            particles.forEach((particle) => {
                const { x, y, z, dt, sigma, rho, beta } = particle.attractor;
                const dx = (sigma * (y - x)) * dt;
                const dy = (x * (rho - z) - y) * dt;
                const dz = (x * y - beta * z) * dt;

                particle.attractor.x += dx;
                particle.attractor.y += dy;
                particle.attractor.z += dz;

                // Update particle position based on the attractor
                const newTrailPoint = {
                    x: canvas.width / 2 + particle.attractor.z * 5,
                    y: canvas.height / 2 + particle.attractor.x * 5,
                };
                particle.trail.push(newTrailPoint);

                // Limit the trail length to create the fading effect
                if (particle.trail.length > 300) {
                    particle.trail.shift();
                }

                // Draw fading track with dynamic color and longer-lasting effect
                ctx.beginPath();
                ctx.moveTo(particle.trail[0].x, particle.trail[0].y);
                for (let i = 1; i < particle.trail.length; i++) {
                    const point = particle.trail[i];
                    ctx.lineTo(point.x, point.y);
                }
                ctx.strokeStyle = `rgba(${particle.color}, 0.5)`;
                ctx.lineWidth = 4;
                ctx.stroke();

                // Draw particle head as a smaller circle
                const lastTrailPoint = particle.trail[particle.trail.length - 1];
                ctx.beginPath();
                ctx.arc(lastTrailPoint.x, lastTrailPoint.y, 2, 0, Math.PI * 2); // Smaller radius
                ctx.fillStyle = `rgba(${particle.color}, 1)`;
                ctx.fill();
            });

            requestAnimationFrame(updateParticles);
        };

        updateParticles();


    }, []);

    return <canvas ref={canvasRef} className="Lorentz" />;
};

export default ParticleBackground;
