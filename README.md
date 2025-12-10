# Satellite Communication Model (Promela / SPIN)

This project implements a simplified satellite communication system in **Promela** and verifies its behavior using **SPIN**. The system consists of a coordinator, a timekeeper, and three satellites communicating with ground stations through synchronized channels.

> This repository was created for a university assignment on formal modeling and verification.

## What the Model Includes
- Time-slot based scheduling of satellite transmissions  
- Blocking synchronous communication (`!` / `?`)  
- Per-satellite message buffers  
- Coordinator logic for granting channel access  
- LTL properties for safety, liveness, and fairness

## Verified Properties
- Mutual exclusion of slot grants  
- Eventual processing of satellite buffers  
- Fairness: each satellite is granted access infinitely often  
- Deadlock freedom
