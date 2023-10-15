import matplotlib.pyplot as plt
import numpy as np

sigma = 10
rho = 28
beta = 8/3

def lorenz_attractor(x, y, z, sigma=sigma, rho=rho, beta=beta):
    x_dot = sigma * (y - x)
    y_dot = x * rho - y - x * z
    z_dot = x * y - beta * z
    return x_dot, y_dot, z_dot

dt = 0.01
num_steps = 10000
x, y, z = [1], [0], [0.1]
for _ in range(num_steps):
    x_dot, y_dot, z_dot = lorenz_attractor(x[-1], y[-1], z[-1])
    x.append(x[-1] + x_dot * dt)
    y.append(y[-1] + y_dot * dt)
    z.append(z[-1] + z_dot * dt)

plt.figure(figsize=(8, 6), facecolor='black')
plt.plot(x, y, color='cyan', linewidth=0.5)

plt.gca().set_facecolor((0, 0, 0, 1))
plt.grid(False)


plt.savefig('lorenz_attractor.png', bbox_inches='tight', facecolor='black', transparent=True)

plt.show()
