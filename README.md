# Smart Contract Architecture

VibesFlow implements a modular smart contract system on the Metis blockchain that enables real-time asset creation, delegation, and monetization through vibestreams.

## Contract Overview

The VibesFlow protocol consists of four core contracts:

<CardGroup cols={2}>
  <Card title="VibeFactory" icon="industry" href="/contracts/vibe-factory">
    Creates RTA NFTs and manages delegation
  </Card>
  <Card title="PPM Contract" icon="clock" href="/contracts/ppm">
    Handles pay-per-minute streaming payments
  </Card>
  <Card title="VibeKiosk" icon="ticket" href="/contracts/vibe-kiosk">
    Manages ticket sales for vibestreams
  </Card>
  <Card title="Subscriptions" icon="calendar" href="/contracts/subscriptions">
    Handles Vibe Market access subscriptions
  </Card>
</CardGroup>

## Architecture Principles

### Modular Design
Each contract handles a specific domain of functionality, allowing for independent upgrades and maintenance.

### Gas Optimization
All contracts implement gas-efficient patterns with minimal external calls and optimized storage layouts.

### Security First
- Reentrancy protection on all payable functions
- Access control with role-based permissions
- Emergency pause functionality where appropriate
- Comprehensive input validation

## Key Features

### Real-Time Assets (RTAs)
NFTs that acquire value in real-time through streaming activities, implemented via the PPM contract's time-based payment system.

### Integrated Delegation
Built-in delegation system allows creators to authorize others to manage their vibestreams without transferring ownership.

### Revenue Distribution
Automatic 80/20 split between creators and treasury across all monetization mechanisms.

### Cross-Contract Integration
Seamless interaction between contracts through standardized interfaces and event-driven architecture.