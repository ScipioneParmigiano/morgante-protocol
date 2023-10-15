// Heading.js

import React from 'react';
import Wavify from 'react-wavify';
import './Heading.css';

const Heading = ({ text }) => {
    return (
        <div className="heading-container">
            <Wavify
                className="wave"
                fill="#00c6ff"
                paused={false}
                options={{
                    height: 20,
                    amplitude: 30,
                    speed: 0.15,
                    points: 4
                }}
            >
                <div className="heading-text">
                    {text.split('').map((char, index) => (
                        <span key={index} style={{ position: 'relative', display: 'inline-block' }}>
                            {char}
                        </span>
                    ))}
                </div>
            </Wavify>
        </div>
    );
};

export default Heading;
