# Swappee Contracts

A collection of smart contracts for the Swappee protocol.

## Overview

This repository contains the smart contracts for the Swappee protocol. The project is built using Foundry and Node for package dependencies.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Bun](https://bun.sh/) (JavaScript runtime)
- Node.js (for TypeScript support)

## Installation

1. Clone the repository.

2. Install dependencies:

```bash
bun install
```

3. Install Foundry dependencies:

```bash
forge install
```

## Project Structure

- `src/` - Main source code directory for Solidity contracts
- `test/` - Test files for the contracts
- `script/` - Deployment and utility scripts
- `lib/` - External dependencies

## Development

### Compiling Contracts

```bash
forge compile
```

### Running Tests

```bash
forge test
```

## Configuration

The project is configured with the following settings:

- Solidity version: 0.8.28
- EVM version: Cancun

## Dependencies

- OpenZeppelin Contracts v5.1.0
- OpenZeppelin Contracts Upgradeable v5.1.0
- Solady v0.1.14

## License

MIT
